<p align="center">
  <img src="Resources/Brand/sswitcher-logo.png" width="112" alt="Shoev Switcher">
</p>

<p align="center">
  <img src="Resources/Brand/github-banner.svg" width="100%" alt="SHOEV SYSTEMS — Shoev Switcher">
</p>

<p align="center">
  <a href="https://github.com/TiDazai/Shoev-Switcher/actions/workflows/ci.yml"><img src="https://github.com/TiDazai/Shoev-Switcher/actions/workflows/ci.yml/badge.svg" alt="macOS CI"></a>
  <a href="https://github.com/TiDazai/Shoev-Switcher/releases"><img src="https://img.shields.io/github/v/release/TiDazai/Shoev-Switcher?color=d9ad55&amp;labelColor=591124&amp;label=release" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-303030" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-native-d9ad55?labelColor=591124" alt="Native Swift">
</p>

<p align="center">
  <strong>Русский и английский без лишних переключений.</strong><br>
  Нативный переключатель раскладки. Встроенные словари. Всё локально.
</p>

<p align="center">
  <a href="https://github.com/TiDazai/Shoev-Switcher/releases/latest/download/Shoev-Switcher.dmg"><strong>Скачать для Mac · DMG</strong></a>
  &nbsp; · &nbsp;
  <a href="https://github.com/TiDazai/Shoev-Switcher/releases/latest/download/Shoev-Switcher-Windows-x64.zip">Windows x64</a>
  &nbsp; · &nbsp;
  <a href="CHANGELOG.md">Что нового</a>
</p>

# Shoev Switcher — автоматический переключатель раскладки

Разработано компанией **SHOEV SYSTEMS**. Автор — **Shoev Timur (TiDazai)**.

Shoev Switcher is an offline Russian–English keyboard layout switcher for macOS and Windows, made by SHOEV SYSTEMS.

## Просто продолжай писать

Shoev Switcher распознаёт слово, набранное в неверной раскладке, исправляет его после пробела или знака препинания и переключает активный язык ввода. Живёт в строке меню: только кошка, без иконки в Dock.

| Набрано | Получится |
| --- | --- |
| `ghbdtn` | привет |
| `f vj;yj` | а можно |
| `руддщ` | hello |

Корректные английские слова вроде `hi` не нужно переводить. Для неоднозначных слов учитываются частоты, последние слова фразы и личные правила — автоматическое распознавание не всегда может угадать намерение.

Enter, Shift+Enter и Tab проходят в приложение без перехвата: отправку сообщения, перенос строки и переход между полями определяет сам редактор. Автоматическое исправление выполняется на пробеле или знаке препинания, не на Enter.

## SHOEV SYSTEMS

Приложения SHOEV SYSTEMS для работы с русским и английским текстом:

- **Shoev Switcher** — исправление неверной раскладки и автоматическое переключение RU ↔ EN.
- **[Shoev Spell](https://github.com/TiDazai/Shoev-Spell)** — исправление опечаток, заглавные буквы и помощь с русской пунктуацией.

Приложения самостоятельные: Switcher меняет раскладку, Spell проверяет написание. Их можно использовать вместе или по отдельности.

## Установка на Mac

1. Открой [DMG](https://github.com/TiDazai/Shoev-Switcher/releases/latest/download/Shoev-Switcher.dmg) и перетащи приложение в **Applications**.
2. Запусти Shoev Switcher.
3. Разреши **Мониторинг ввода** и **Универсальный доступ** в настройках macOS.
4. Убедись, что добавлены русская и английская раскладки.

Поддерживаются **macOS 13+**, **Apple Silicon и Intel** одним приложением.

Текущая общедоступная сборка не нотарифицирована Apple. При первом запуске macOS может её заблокировать: используй «Всё равно открыть» в «Системные настройки → Конфиденциальность и безопасность», если доверяешь источнику.

## Под рукой

- **Автоматическое RU ↔ EN** — словарь уже внутри, сеть не нужна.
- **Двойной Shift** — вручную перевести выделение, текущее или последнее слово. Левый или правый Shift выбирается в настройках.
- **Backspace после исправления** — вернуть исходное слово без скрытых исключений.
- **Флаг возле мыши** — язык ввода над текстовым полем, без привязки к каретке.
- **Настройки по функциям** — контекст, флаг, уведомления, память раскладки, обучение и дневник можно отключить отдельно.
- **Исключения по приложениям** — терминалы и IDE исключены по умолчанию.
- **Дневник и правила** — поиск, «никогда не менять», «всегда менять», свои слова, импорт и экспорт JSON.
- **Самообучение** — повторное ручное исправление может стать личным правилом; выученные правила можно удалить.
- **Автозапуск и память раскладки** — по желанию.

## Словари внутри

**7 120 939 записей:** 4 020 787 русских и 3 100 152 английских слов и словоформ. В корпус входят морфология, имена, фамилии, географические названия, бренды, технические термины, сленг и ненормативная лексика.

Это большой корпус, а не обещание знать каждое существующее слово. Личные словари дополняют его без пересборки приложения. Данные и их лицензии перечислены в [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Текст остаётся на устройстве

Нет облачных API и телеметрии. Журнал и пользовательские правила хранятся локально с шифрованием AES-GCM. Полный дневник набора выключен по умолчанию. Clipboard не изменяется.

Перед заменой Switcher проверяет текущее поле, курсор и исходный текст через Accessibility. В защищённых полях, при Secure Event Input и там, где приложение не позволяет безопасно прочитать и изменить текст, автоматическая замена пропускается. Совместимость зависит от конкретного редактора и поля; универсальная работа во всех приложениях не гарантируется.

Подробнее: [приватность](docs/PRIVACY.md) · [архитектура](docs/ARCHITECTURE.md).

## Windows

Скачай [Windows x64 ZIP](https://github.com/TiDazai/Shoev-Switcher/releases/latest/download/Shoev-Switcher-Windows-x64.zip), распакуй и запусти `Shoev Switcher.exe`. Поддерживаются Windows 10/11 x64; установка .NET не требуется. Реализация Windows отдельная, набор функций и совместимость могут отличаться от macOS. [Подробности](windows/README.md).

## Разработка

macOS — Swift Package, Xcode и Command Line Tools:

```bash
./scripts/prepare-lexicon.sh
swift test
./scripts/create-dmg.sh
```

Результат: `dist/Shoev-Switcher.dmg`. Скрипт создаёт свежую универсальную сборку, проверяет подпись приложения и контрольную сумму образа. Для сохранения разрешений при локальной разработке можно один раз выполнить `./scripts/setup-local-signing.sh`.

Windows:

```powershell
dotnet publish windows/ShoevSwitcher.Windows/ShoevSwitcher.Windows.csproj -c Release -r win-x64 --self-contained true
```

[Сообщить об ошибке](https://github.com/TiDazai/Shoev-Switcher/issues/new/choose) · [Участие в разработке](CONTRIBUTING.md) · [Лицензии словарей](THIRD_PARTY_NOTICES.md)

---

<p align="center"><strong>SHOEV SYSTEMS</strong><br><sub>Небольшие инструменты для повседневной работы.</sub></p>
