# Localization

The app supports Norwegian Bokmål (`nb`), English (`en`), German (`de`) and Spanish (`es`). The default is `system`: match the first supported Mac preferred language, treating `no` and `nn` as Bokmål; otherwise use English. Settings → Language stores an explicit override in `UserDefaults.appLanguage`. Switching languages refreshes views without recreating capture sessions. Existing recording titles and device names are not translated; errors already displayed retain their original text until replaced.

App text lives in `Sources/LewtechRecord/Resources/Translations.json`, keyed by the Norwegian source string. Each entry must have all four translations. Dynamic values use numbered placeholders (`{0}`, `{1}`); preserve their count and indexes. Swift uses `L10n.tr("literal with \(value)")` to keep values separate from translation keys. Do not translate persistence keys, user filenames or device names.

Permission descriptions live in `packaging/{nb,en,de,es}.lproj/InfoPlist.strings` and follow macOS language preferences. The build script includes them in the signed app bundle. Standard system dialogs are controlled by macOS.

Run `scripts/verify.sh` to validate catalog completeness, placeholder parity, language resolution and safe interpolation alongside media regression checks. Build using `scripts/build.sh`. To add another language, extend `AppLanguage`, every catalog entry, the permission resources and `CFBundleLocalizations`, then update the README and user guide. Verify long labels in Settings, Studio and Library at the minimum window size.
