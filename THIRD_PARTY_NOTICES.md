# Third-Party Notices

## RunCat365 cat sprites

- Source: RunCat365 — https://github.com/runcat-dev/RunCat365
- License: Apache License 2.0
- Files bundled: `Sources/TokCatApp/Resources/RunCatCat/cat_0.png` … `cat_4.png`
  (copied **unmodified** from `RunCat365/resources/runners/cat/`)
- Copyright belongs to the RunCat365 authors. See `LICENSE` for the full
  Apache-2.0 license text.

These sprite frames are used as one of the selectable menu-bar animations.
The trademark/name "RunCat" is not used for branding anything in this project;
the animation pack is labelled generically as "Cat (RunCat sprites)".

## HighlighterSwift (vendored)

- Source: HighlighterSwift — https://github.com/smittytone/HighlighterSwift
  (snapshot of v3.1.x, vendored into `Sources/TokCatApp/Highlighter/`)
- License: MIT
- Files bundled: `Sources/TokCatApp/Resources/Highlighter/`
  (`highlight.min.js` and `styles/*.css`, copied **unmodified** from the
  library's `Sources/Assets/`)
- Copyright belongs to the HighlighterSwift authors (Tony Smith and
  contributors). The vendored Swift sources carry their original MIT headers.

Vendoring rationale: SwiftPM 6.1 generates a `Bundle.module` accessor for
resource targets that cannot locate the bundle in a distributed `.app`
(see `Sources/TokCatApp/AppBundle.swift`), so the library is compiled into
the app target with a bundle lookup we control.
