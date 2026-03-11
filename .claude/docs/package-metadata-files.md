# Специальные/метаданные файлы пакетов

Исследовательский документ: какие специальные файлы нужны каждому формату пакета — помимо обычного содержимого (bin, lib, share, etc, var). Фокус на файлах, которые не являются частью FHS-дерева, но критичны для корректной работы формата.

---

## .deb (Debian / Ubuntu)

### Структура пакета

```
package.deb         ← ar-архив
├── debian-binary   ← строка "2.0\n", обязателен
├── control.tar.xz  ← метаданные (контрольная секция)
│   ├── control     ← ОБЯЗАТЕЛЕН: имя, версия, архитектура, описание
│   ├── md5sums     ← генерируется автоматически dpkg/nfpm
│   ├── conffiles   ← список конфигурационных файлов
│   ├── preinst     ← скрипт перед распаковкой
│   ├── postinst    ← скрипт после распаковки
│   ├── prerm       ← скрипт перед удалением
│   └── postrm      ← скрипт после удаления
└── data.tar.xz     ← полезная нагрузка (файлы пакета)
```

### Файлы в data.tar (на целевой системе)

| Файл | Путь | Обязателен | Что будет без него |
|------|------|:----------:|--------------------|
| `copyright` | `/usr/share/doc/<pkg>/copyright` | **Да (Debian Policy)** | Lintian: `no-copyright-file` (ошибка). Пакет установится, но не пройдёт в официальные репозитории |
| `changelog.Debian.gz` | `/usr/share/doc/<pkg>/changelog.Debian.gz` | **Да (Debian Policy)** | Lintian: `no-changelog` (ошибка). Пакет установится, но не пройдёт в официальные репозитории |
| `changelog.gz` | `/usr/share/doc/<pkg>/changelog.gz` | Нет | Lintian: предупреждение, если upstream changelog существует |

### Файлы в control.tar

| Файл | Обязателен | Назначение | Что будет без него |
|------|:----------:|-----------|-------------------|
| `control` | **Да** | Имя, версия, архитектура, зависимости, описание | Пакет не будет корректным deb-архивом |
| `md5sums` | Нет | Контрольные суммы файлов payload | Создаётся автоматически dpkg/nfpm. Без него dpkg не сможет проверить целостность |
| `conffiles` | Нет | Список файлов-конфигов с защитой от перезаписи | Без него конфиги перезаписываются при обновлении без предупреждения. dpkg не будет спрашивать пользователя |
| `preinst` / `postinst` / `prerm` / `postrm` | Нет | Скрипты жизненного цикла | Без них установка/удаление проходят без хуков. Для пакетов без systemd и без пользователей — не нужны |
| `shlibs` / `symbols` | Нет | Информация о предоставляемых shared libraries | Нужны только пакетам, поставляющим `.so` файлы |
| `triggers` | Нет | Триггеры установки (ldconfig, python bytecode и пр.) | Нужны специфическим пакетам |

### Формат conffiles

```
/etc/myapp/config.yaml
/etc/myapp/defaults.yaml
```
Один путь на строку. Файлы из этого списка при обновлении пакета: если пользователь изменил файл — dpkg предлагает выбор (оставить пользовательский / установить новый / показать diff).

### Формат copyright

Стандарт: Machine-readable Debian copyright format (DEP-5). Минимально допустимый вариант — произвольный текстовый файл с текстом лицензии. Кодировка: UTF-8. Файл не сжимается.

### Поведение conffiles без `config|noreplace` в nfpm

При использовании nfpm:
- `type: config` → файл добавляется в `conffiles`, dpkg предлагает выбор при конфликте
- `type: config|noreplace` → файл добавляется в `conffiles` с пометкой noreplace (dpkg устанавливает `.dpkg-new` если файл изменён)
- `type: file` → файл НЕ попадает в `conffiles`, при обновлении перезаписывается без предупреждения

### Автогенерация в nfpm

nfpm **автоматически создаёт**:
- `control` (из полей конфига)
- `md5sums` (хэши всех файлов payload)
- `conffiles` (из файлов с type: config или config|noreplace)

nfpm **не создаёт автоматически**:
- `copyright` — пользователь должен добавить файл в `contents` с `dst: /usr/share/doc/<pkg>/copyright`
- `changelog.Debian.gz` — пользователь должен подготовить и добавить в `contents`

---

## .rpm (Red Hat / CentOS / Fedora / SUSE)

### Структура пакета

RPM — бинарный формат с заголовком (Header) и payload (CPIO-архив).

```
package.rpm
├── Lead       ← устаревший заголовок (совместимость)
├── Signature  ← подпись пакета (GPG/SHA)
├── Header     ← все метаданные (имя, версия, скрипты, файловый манифест)
└── Payload    ← CPIO-архив с файлами (сжатый gzip/zstd/xz)
```

Метаданные хранятся в Header — отдельных физических файлов нет, всё встроено в структуру RPM.

### Скриптлеты (встроены в Header)

| Скриптлет | Когда выполняется | Обязателен |
|-----------|------------------|:----------:|
| `%pre` | До установки файлов | Нет |
| `%post` | После установки файлов | Нет |
| `%preun` | До удаления файлов | Нет |
| `%postun` | После удаления файлов | Нет |
| `%pretrans` | До начала транзакции RPM (до %pre) | Нет |
| `%posttrans` | После завершения транзакции (после %postun) | Нет |
| `%verify` / `%verifyscript` | При `rpm --verify` | Нет |
| `%triggerprein`, `%triggerin`, `%triggerun`, `%triggerpostun` | Триггеры от других пакетов | Нет |

Скриптлет по умолчанию: `/bin/sh`. Можно сменить: `%post -p /usr/bin/python3`.

### Файлы на целевой системе

| Атрибут в spec | Путь назначения | Назначение | Что будет без него |
|----------------|-----------------|-----------|-------------------|
| `%license LICENSE` | `/usr/share/licenses/<pkg>/LICENSE` | Файл лицензии | **`%license` нельзя отфильтровать** — лицензия всегда должна присутствовать. Fedora/RHEL обязывают включать |
| `%doc README` | `/usr/share/doc/<pkg>/README` | Документация | Нет жёстких требований, но recommended |
| `%config /etc/app.conf` | указанный путь | Конфигурационный файл с защитой | Без %config файл перезаписывается при обновлении |
| `%config(noreplace) /etc/app.conf` | указанный путь | Конфиг: при обновлении → `.rpmnew` если изменён | Рекомендуется для большинства конфигов |
| `%ghost /var/log/app.log` | указанный путь | Файл, о котором RPM знает, но не устанавливает | Без %ghost RPM не отслеживает файл (логи, pid-файлы) |

### Обязательные поля spec-файла

```
Name:     myapp
Version:  1.0.0
Release:  1%{?dist}
Summary:  One-line description
License:  MIT
```

Поле `License` — обязательно. В Fedora/RHEL требуется SPDX-идентификатор лицензии.

### Нет changelog в пакете

В отличие от deb, RPM changelog хранится **в spec-файле** (секция `%changelog`) и встраивается в заголовок пакета. Отдельного changelog-файла на целевой системе нет.

### Обязательные vs опциональные

- **Обязательны**: Name, Version, Release, Summary, License, %files секция
- **Опциональны**: все скриптлеты, %doc, Source, URL, BuildRequires
- `%license` — технически опционален в rpm-build, но **обязателен для Fedora/RHEL/Fedora packaging guidelines**

---

## .apk (Alpine Linux)

### Структура пакета

APK — gzip tar-архив со специфической структурой. Фактически: несколько tar-слоёв в одном файле.

```
package.apk
├── .SIGN.RSA.<keyname>.pub  ← RSA-подпись (первый слой tar)
├── .PKGINFO                  ← метаданные пакета (второй слой tar)
└── <файлы пакета>           ← данные (тот же слой tar)
```

### Специальные файлы

| Файл | Местоположение | Обязателен | Назначение |
|------|---------------|:----------:|-----------|
| `.PKGINFO` | корень архива | **Да** | Имя, версия, архитектура, описание, зависимости, maintainer. Без него apk не может работать с пакетом |
| `.SIGN.RSA.<keyname>.pub` | корень архива | Только при подписи | RSA-подпись. Без подписи пакет можно установить с флагом `--allow-untrusted`, но не из официальных репозиториев |
| `.pre-install` | корень архива | Нет | Скрипт до установки. В APKBUILD: `install=$pkgname.pre-install` |
| `.post-install` | корень архива | Нет | Скрипт после установки |
| `.pre-upgrade` | корень архива | Нет | Скрипт до обновления |
| `.post-upgrade` | корень архива | Нет | Скрипт после обновления |
| `.pre-deinstall` | корень архива | Нет | Скрипт до удаления |
| `.post-deinstall` | корень архива | Нет | Скрипт после удаления |
| `.trigger` | корень архива | Нет | Скрипт-триггер (специфика Alpine) |

### .PKGINFO формат

```
# Generated by abuild 3.12.0
pkgname = myapp
pkgver = 1.0.0-r0
arch = x86_64
size = 12345
pkgdesc = My application
url = https://example.com
builddate = 1700000000
packager = Alpine Linux
depend = so:libc.musl-x86_64.so.1
```

Генерируется автоматически abuild или nfpm из метаданных конфига.

### Особенности APK

- Нет отдельного `conffiles` — конфиги указываются в `install_if` или `triggers` секциях APKBUILD. При `apk upgrade` конфиги в `/etc` не перезаписываются, если изменены пользователем (защита встроена в apk).
- Нет `%license` / copyright механизма — лицензионный файл добавляется в payload как обычный файл (`/usr/share/licenses/<pkg>/LICENSE`)
- Нет отдельного changelog — информация о пакете в `.PKGINFO`

### Скрипты install в nfpm → APK

nfpm поддерживает `scripts.preinstall` и `scripts.postinstall` для APK. `scripts.preremove` и `scripts.postremove` поддерживаются через `overrides.apk`. Скрипты упаковываются в `.pre-install`, `.post-install`, `.pre-deinstall`, `.post-deinstall` соответственно.

---

## .pkg.tar.zst (Arch Linux)

### Структура пакета

```
package.pkg.tar.zst
├── .PKGINFO    ← метаданные пакета (обязателен)
├── .BUILDINFO  ← информация для воспроизводимых сборок
├── .MTREE      ← манифест файлов с хэшами и временными метками
├── .INSTALL    ← скрипты жизненного цикла (опционален)
└── <файлы пакета>
```

### Специальные файлы

| Файл | Обязателен | Назначение | Что будет без него |
|------|:----------:|-----------|-------------------|
| `.PKGINFO` | **Да** | Имя, версия, архитектура, зависимости, описание. pacman читает этот файл | Пакет не может быть установлен pacman |
| `.BUILDINFO` | Нет | Окружение сборки для воспроизводимых сборок (builddate, builddir, packager, buildenv, etc.) | Пакет работает, но не поддерживает reproducible builds |
| `.MTREE` | Нет | Хэши (SHA256) и метаданные файлов для проверки целостности | Без него pacman не может проверить целостность при установке |
| `.INSTALL` | Нет | Функции жизненного цикла пакета | Без него нет pre/post install хуков |
| `.Changelog` | Нет | Changelog пакета | Нет changelog в пакете |

### .INSTALL файл

Содержит bash-функции:

```bash
pre_install() {
    # Вызывается до распаковки. $1 = новая версия
    :
}
post_install() {
    # Вызывается после распаковки. $1 = новая версия
    :
}
pre_upgrade() {
    # Вызывается до обновления. $1 = новая версия, $2 = старая версия
    :
}
post_upgrade() {
    # Вызывается после обновления. $1 = новая версия, $2 = старая версия
    :
}
pre_remove() {
    # Вызывается до удаления. $1 = старая версия
    :
}
post_remove() {
    # Вызывается после удаления. $1 = старая версия
    :
}
```

В PKGBUILD указывается через поле `install=myapp.install`.

### Нет conffiles механизма

В Arch нет встроенного механизма защиты конфигов от перезаписи (аналог `conffiles` в deb). pacman перезаписывает все файлы при обновлении, кроме тех, что указаны в `backup=()` в PKGBUILD (попадает в `.PKGINFO`). Файлы из `backup=()` при конфликте сохраняются как `.pacsave` или `.pacnew`.

### Лицензионный файл

По конвенции Arch: `/usr/share/licenses/<pkg>/LICENSE`. Не технически обязателен, но требуется Arch packaging guidelines.

### Генерация в nfpm

nfpm (при `packager: archlinux`) автоматически генерирует:
- `.PKGINFO` из метаданных конфига
- `.BUILDINFO` (базовая информация о сборке)
- `.MTREE` (хэши и метаданные файлов payload)
- `.INSTALL` — только если указаны scripts в конфиге

---

## .msi (Windows Installer / WiX)

### Структура MSI

MSI — бинарный формат OLE Compound Document. Содержит набор таблиц базы данных (не файлы в обычном понимании). Файлы пакуются в CAB-архив, встраиваемый в MSI или отдельный.

### Специальные ресурсы для UI

| Ресурс | Где объявляется в WiX | Тип | Обязателен | Назначение |
|--------|----------------------|-----|:----------:|-----------|
| `.ico` файл иконки | `<Icon>` + `ARPPRODUCTICON` | ICO | Нет | Иконка в Add/Remove Programs. Без неё — нет иконки в ARP |
| `license.rtf` / `license.txt` | `<WixVariable Id="WixUILicenseRtf">` | RTF/TXT | **Да для WixUI** | Текст лицензии в диалоге установщика. Без него WixUI откажется компилироваться |
| `bannertop.bmp` | `<WixVariable Id="WixUIBannerBmp">` | BMP 493×58 | Нет | Шапка диалогов установщика |
| `dialog.bmp` | `<WixVariable Id="WixUIDialogBmp">` | BMP 493×312 | Нет | Фон Welcome-диалога |
| `ExclamationIcon.ico` | `<WixVariable Id="WixUIExclamationIco">` | ICO | Нет | Иконка предупреждения в UI |
| `InfoIcon.ico` | `<WixVariable Id="WixUIInfoIco">` | ICO | Нет | Иконка информации в UI |
| `NewIcon.ico` | `<WixVariable Id="WixUINewIco">` | ICO | Нет | Иконка "новая папка" |
| `UpIcon.ico` | `<WixVariable Id="WixUIUpIco">` | ICO | Нет | Иконка "вверх" |

### Важные особенности MSI

**Для wixl (msitools, кросс-компиляция):**
- wixl не поддерживает UI диалоги вообще — установщик работает в тихом режиме
- Нет WixUI → нет требований к license.rtf, баннерам, диалогам
- Лицензионный файл при желании добавляется в `<File>` как обычный файл в каталог установки

**Для WiX Toolset (Windows):**
- Без `WixUILicenseRtf` при использовании `<UIRef Id="WixUI_Minimal"/>` и аналогов — ошибка компиляции
- Рекомендуется включать `LICENSE.txt` или `LICENSE.rtf` в компонент установки (установится в директорию продукта)

**Файлы, обязательные по формату MSI:**
- `.wxs` источник (для сборки) — не входит в пакет
- Результирующий `.msi` содержит CAB с файлами и таблицы базы данных — нет "свободных" метафайлов

### Что включать для соответствия лучшим практикам

```xml
<!-- Иконка в Add/Remove Programs -->
<Icon Id="ProductIcon" SourceFile="resources/app.ico" />
<Property Id="ARPPRODUCTICON" Value="ProductIcon" />

<!-- URL продукта в Add/Remove Programs -->
<Property Id="ARPHELPLINK" Value="https://example.com/support" />
<Property Id="ARPURLINFOABOUT" Value="https://example.com" />

<!-- Лицензия как файл в директории установки -->
<File Id="LicenseFile" Source="LICENSE.txt" />
```

---

## .pkg (macOS pkgbuild / productbuild)

### Структура пакета

**Компонентный пакет** (pkgbuild):
```
component.pkg   ← xar-архив
├── PackageInfo ← метаданные пакета (XML)
├── Bom         ← Bill of Materials (список файлов с хэшами)
├── Payload     ← cpio-архив с файлами (сжатый gzip)
└── Scripts     ← cpio-архив со скриптами (если указаны)
```

**Дистрибутивный пакет** (productbuild):
```
installer.pkg   ← xar-архив
├── Distribution       ← distribution.xml (обязателен)
├── Resources/         ← опциональные ресурсы
│   ├── welcome.rtf    ← Welcome-экран инсталлятора
│   ├── readme.rtf     ← README-экран
│   ├── license.rtf    ← лицензионный экран (пользователь должен принять)
│   ├── conclusion.rtf ← финальный экран
│   └── background.png ← фоновое изображение
└── <component.pkg>    ← вложенные компонентные пакеты
```

### Специальные файлы

| Файл | Обязателен | Назначение | Что будет без него |
|------|:----------:|-----------|-------------------|
| `PackageInfo` | **Да** (генерируется pkgbuild) | Идентификатор, версия, install-location, зависимости скриптов | Пакет не является корректным .pkg |
| `Bom` | **Да** (генерируется pkgbuild) | Bill of Materials — список файлов для установки/проверки | Installer.app не сможет установить пакет |
| `Payload` | Нет (если `--nopayload`) | Файлы для установки на целевую систему | Пакет устанавливает только скрипты |
| `Scripts/preinstall` | Нет | Скрипт до установки payload | Без него нет пред-установочных хуков |
| `Scripts/postinstall` | Нет | Скрипт после установки payload | Без него нет пост-установочных хуков |
| `Distribution` | **Да для productbuild** | XML с описанием инсталлятора | Без него productbuild не работает |
| `Resources/license.rtf` | Нет | Лицензия, которую пользователь принимает | Без неё нет экрана принятия лицензии |
| `Resources/welcome.rtf` | Нет | Welcome-экран | Инсталлятор начинает сразу с выбора места |
| `Resources/background.png` | Нет | Фон окна инсталлятора | Стандартный серый фон |

### Скрипты pkgbuild

```
scripts/
├── preinstall   ← chmod 755, shebang обязателен
└── postinstall  ← chmod 755, shebang обязателен
```

Аргументы скриптов при вызове:
- `$1` — путь к .pkg файлу
- `$2` — install-location (путь назначения)
- `$3` — путь к тому (обычно `/`)

Если `preinstall` завершается с кодом != 0 → установка прерывается.
Если `postinstall` завершается с кодом != 0 → предупреждение (файлы уже скопированы).

### LaunchDaemon / LaunchAgent (специфика macOS)

Для системных сервисов в macOS используются LaunchDaemon/LaunchAgent plist-файлы:

| Файл | Путь | Назначение |
|------|------|-----------|
| `com.company.app.plist` | `/Library/LaunchDaemons/` | Системный демон (запускается как root, при загрузке) |
| `com.company.app.plist` | `/Library/LaunchAgents/` | Агент для всех пользователей (при входе) |
| `com.company.app.plist` | `~/Library/LaunchAgents/` | Агент для конкретного пользователя |

Активируется в `postinstall`:
```bash
launchctl load -w /Library/LaunchDaemons/com.company.app.plist
```

Аналог systemd для macOS — нет автоматического механизма типа `systemctl enable` при установке пакета.

---

## .dmg (macOS disk image)

### Что такое DMG

DMG — дисковый образ, а не установочный пакет в классическом смысле. Содержит файловую систему (обычно HFS+/APFS) с файлами. Нет встроенного механизма установки, скриптов, лицензионного экрана.

### Специальные файлы внутри DMG

| Файл/директория | Назначение | Обязателен |
|----------------|-----------|:----------:|
| `<AppName>.app` | Само приложение | Да (для GUI-приложений) |
| `Applications` symlink → `/Applications` | Ярлык для drag-and-drop установки | Нет (конвенция) |
| `.background/background.png` | Фоновое изображение (скрытая директория) | Нет |
| `.DS_Store` | Настройки Finder (размер окна, позиции иконок) | Нет (генерируется автоматически через AppleScript/Finder) |
| `README.txt` | Инструкция по установке | Нет |
| `LICENSE.txt` | Текст лицензии | Нет |

### Нет installer-механизма

DMG не имеет:
- Скриптов pre/post install
- Механизма conffiles / конфигов
- Системы зависимостей
- Автоматической интеграции с системой (PATH, LaunchDaemons)

Для CLI-утилит DMG требует ручной установки пользователем (drag-to-folder). Поэтому для CLI предпочтительнее `.pkg`.

### Подпись

С macOS 10.15+ Gatekeeper блокирует неподписанные DMG. Необходимо:
1. Подписать приложение (`codesign`) перед помещением в DMG
2. Подписать DMG (`codesign`)
3. Нотаризировать DMG (`notarytool`)
4. Staple нотаризацию (`stapler`)

---

## .tar.gz (архив)

### Структура

Простой gzip-сжатый tar-архив. Нет встроенного механизма метаданных, скриптов, зависимостей.

### Конвенции для содержимого

Два распространённых подхода:

**1. FHS-структура (overlay)** — архив содержит файловое дерево для распаковки в `/`:
```
usr/bin/myapp
usr/share/man/man1/myapp.1.gz
usr/share/doc/myapp/README.md
usr/share/doc/myapp/LICENSE
etc/myapp/config.yaml
```

**2. Standalone-структура** — всё в одной директории:
```
myapp-1.0.0-linux-amd64/
├── myapp           ← исполняемый файл
├── README.md
├── LICENSE
└── CHANGELOG.md
```

### Рекомендуемый файловый состав

| Файл | Путь (standalone) | Обязателен | Назначение |
|------|------------------|:----------:|-----------|
| Бинарник | `myapp` или `bin/myapp` | **Да** | Исполняемый файл |
| `LICENSE` | корень или `LICENSE` | Нет (конвенция) | Текст лицензии |
| `README.md` | корень | Нет (конвенция) | Инструкция пользователя |
| `CHANGELOG.md` | корень | Нет | История изменений |

Нет специальных требований от формата — только конвенции.

---

## .ipk (OpenWRT / Entware / opkg)

### Структура пакета

IPK — gzip tar-архив, содержащий вложенные архивы (аналог deb):

```
package.ipk   ← gzip tar
├── debian-binary   ← строка "2.0" (совместимость с deb)
├── control.tar.gz  ← метаданные
│   ├── control     ← ОБЯЗАТЕЛЕН: имя, версия, архитектура, описание
│   ├── conffiles   ← список конфигурационных файлов
│   ├── preinst     ← скрипт до установки
│   ├── postinst    ← скрипт после установки
│   ├── prerm       ← скрипт до удаления
│   └── postrm      ← скрипт после удаления
└── data.tar.gz     ← полезная нагрузка (файлы)
```

### Файлы control.tar.gz

| Файл | Обязателен | Назначение |
|------|:----------:|-----------|
| `control` | **Да** | Имя, версия, архитектура, описание, зависимости, maintainer |
| `conffiles` | Нет | Список конфигурационных файлов (те же правила, что в deb) |
| `preinst` | Нет | Скрипт до установки (должен быть исполняемым) |
| `postinst` | Нет | Скрипт после установки |
| `prerm` | Нет | Скрипт до удаления |
| `postrm` | Нет | Скрипт после удаления |

### Формат control

```
Package: myapp
Version: 1.0.0-1
Depends: libc
Architecture: aarch64_cortex-a53
Maintainer: Name <email>
Description: My application for OpenWRT
```

### Особенности IPK (OpenWRT-среда)

- Целевая среда — роутеры, IoT-устройства с минимальными ресурсами
- Нет systemd — сервисы запускаются через `/etc/init.d/` (procd init.d скрипты)
- Нет copyright/changelog требований (не Debian-репозитории)
- Скрипты обычно минимальны (ash/busybox-совместимый sh)
- Типичный постinstall для сервиса:
  ```bash
  #!/bin/sh
  /etc/init.d/myapp enable
  /etc/init.d/myapp start
  ```

### Генерация в nfpm

nfpm (при `packager: ipk`) автоматически генерирует:
- `control` из метаданных конфига
- `conffiles` из файлов с type: config или config|noreplace
- Включает скрипты из `scripts:` секции

---

## Сводная таблица

### Скрипты жизненного цикла

| Событие | .deb | .rpm | .apk | .pkg.tar.zst | .pkg (macOS) | .ipk |
|---------|------|------|------|--------------|--------------|------|
| До установки | `preinst` | `%pre` | `.pre-install` | `pre_install()` | `preinstall` | `preinst` |
| После установки | `postinst` | `%post` | `.post-install` | `post_install()` | `postinstall` | `postinst` |
| До обновления | `preinst upgrade` | `%pre` | `.pre-upgrade` | `pre_upgrade()` | — | `preinst` |
| После обновления | `postinst configure` | `%post` | `.post-upgrade` | `post_upgrade()` | — | `postinst` |
| До удаления | `prerm` | `%preun` | `.pre-deinstall` | `pre_remove()` | — | `prerm` |
| После удаления | `postrm` | `%postun` | `.post-deinstall` | `post_remove()` | — | `postrm` |
| До транзакции | — | `%pretrans` | — | — | — | — |
| После транзакции | — | `%posttrans` | — | — | — | — |

### Конфигурационные файлы (защита от перезаписи)

| Формат | Механизм | Файл/поле | Поведение при обновлении |
|--------|---------|-----------|------------------------|
| .deb | `conffiles` в DEBIAN/ | Один путь на строку | dpkg предлагает выбор при конфликте |
| .rpm | `%config(noreplace)` | В %files секции spec | Устанавливается `.rpmnew` если файл изменён |
| .apk | встроен в apk | Нет conffiles файла | apk автоматически сохраняет изменённые файлы в /etc |
| .pkg.tar.zst | `backup=()` в PKGBUILD | В .PKGINFO | Создаётся `.pacnew` если файл изменён |
| .msi | — | Нет механизма | WI не управляет конфигами |
| .pkg (macOS) | — | Нет механизма | postinstall скрипт управляет вручную |
| .tar.gz | — | Нет механизма | Ручная распаковка |
| .ipk | `conffiles` в control.tar.gz | Один путь на строку | Аналогично deb |

### Лицензионные файлы

| Формат | Путь | Обязателен для публикации |
|--------|------|:------------------------:|
| .deb | `/usr/share/doc/<pkg>/copyright` | **Да** (Debian Policy) |
| .rpm | `/usr/share/licenses/<pkg>/LICENSE` (`%license`) | **Да** (Fedora/RHEL guidelines) |
| .apk | `/usr/share/licenses/<pkg>/LICENSE` (конвенция) | Нет |
| .pkg.tar.zst | `/usr/share/licenses/<pkg>/LICENSE` (конвенция) | Нет |
| .msi | Файл в директории установки | Нет |
| .pkg (macOS) | В Resources/ дистрибутивного пакета | Нет |
| .tar.gz | `LICENSE` в корне архива (конвенция) | Нет |
| .ipk | Нет стандарта | Нет |

### Системные сервисы

| Формат | Механизм | Путь | Активация |
|--------|---------|------|----------|
| .deb / .rpm / .apk / .pkg.tar.zst | systemd | `/lib/systemd/system/<name>.service` или `/usr/lib/systemd/system/` | `systemctl enable` в postinstall |
| .pkg (macOS) | LaunchDaemon | `/Library/LaunchDaemons/<id>.plist` | `launchctl load -w` в postinstall |
| .msi | Windows Service | Через `<ServiceInstall>` в WiX | WiX управляет автоматически |
| .ipk | procd / init.d | `/etc/init.d/<name>` | `/etc/init.d/<name> enable && start` в postinst |
| .tar.gz | — | Ручная установка | — |
| .dmg | — | Нет механизма | — |

### Desktop-файлы (GUI-приложения)

| Файл | Путь | Назначение | Обязателен |
|------|------|-----------|:----------:|
| `<appname>.desktop` | `/usr/share/applications/` | Запись в меню приложений, иконка, команда запуска | Нет, но без него GUI-приложение не появляется в меню |

Обязательные поля .desktop файла:
- `Type=Application`
- `Name=<Название>`

Рекомендуемые поля:
- `Exec=<команда>`
- `Icon=<имя иконки>`
- `Categories=<категории>`
- `Comment=<описание>`

Иконки устанавливаются в `/usr/share/icons/hicolor/<size>/apps/<appname>.png` (XDG Icon Theme Specification).

---

## Автогенерация vs ручное предоставление (nfpm)

| Файл | deb | rpm | apk | archlinux | ipk |
|------|:---:|:---:|:---:|:---------:|:---:|
| control / .PKGINFO | авто | в Header | авто (.PKGINFO) | авто (.PKGINFO) | авто |
| md5sums | авто | в Header | — | авто (.MTREE) | — |
| conffiles | из `type: config*` | `%config` в spec | встроен в apk | `backup=()` | из `type: config*` |
| install-скрипты | из `scripts:` | из `scripts:` | из `scripts:` | из `scripts:` | из `scripts:` |
| copyright / %license | **вручную** в contents | **вручную** в contents | **вручную** в contents | **вручную** в contents | — |
| changelog.Debian.gz | **вручную** в contents | нет (в Header) | нет | нет | нет |
| .BUILDINFO | — | — | — | авто | — |
| .INSTALL | — | — | — | из `scripts:` | — |

---

## Ссылки

- [Debian Policy Manual — Chapter 3: Binary packages](https://www.debian.org/doc/debian-policy/ch-binary.html)
- [Debian Policy Manual — Chapter 10: Files](https://www.debian.org/doc/debian-policy/ch-files.html)
- [Debian Policy Manual — Chapter 6: Maintainer scripts](https://www.debian.org/doc/debian-policy/ch-maintainerscripts.html)
- [RPM spec manual](https://rpm-software-management.github.io/rpm/manual/spec.html)
- [Alpine APK packages](https://wiki.alpinelinux.org/wiki/Creating_an_Alpine_package)
- [Arch Linux PKGBUILD](https://wiki.archlinux.org/title/PKGBUILD)
- [Arch Linux Creating packages](https://wiki.archlinux.org/title/Creating_packages)
- [XDG Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
- [Apple Distribution XML Reference](https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/DistributionDefinitionRef/)
- [nfpm configuration](https://nfpm.goreleaser.com/configuration/)
- [OpenWRT package creation](https://openwrt.org/docs/guide-developer/packages)
