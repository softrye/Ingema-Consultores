# Nothing Files — Documents port checkpoint

Primary donor: `Nothing-Files-main.zip`, extracted without modifying originals to
`C:/Users/PC-02/Documents/DOCUMENTOS/Nothing-Files-main-src/Nothing-Files-main`.
Android package `com.nothing.files`, versionName `1.0`, versionCode `1`.
Main and stable have identical source; only README.md differs.

The new `src/documents/` implementation adapts behavior from
`app/src/main/java/com/nothing/files/FileViewModel.kt` and `MainActivity.kt`.
Donor license: GNU GPL version 3, preserved in
`docs/nothing-port/LICENSE-Nothing-Files`. The adapted files carry SPDX headers.
This checkpoint does not change the licensing declarations of unrelated host code.

The donor uses AndroidX Compose Material Filled icons. The corresponding Material
Icons font and codepoints were obtained from Google's material-design-icons
repository, with its license preserved alongside the font in
`qml/Mobile/documents/assets/LICENSE-MaterialIcons`.
Source: https://github.com/google/material-design-icons/tree/master/font
Font SHA256: EF149F08BDD2FF09A4E2C8573476B7B0F3FBB15B623954ADE59899E7175BEDDA.

No Nothing Dot font is present in the donor. Actual Type.kt uses system monospace
for display/headline/labels and sans-serif for body text.
