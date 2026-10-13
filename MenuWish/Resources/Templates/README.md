# Blank native documents

These are locally created, empty documents saved by Apple's Numbers, Pages, and
Keynote 26.3.1 (Creator Studio) on 2026-09-28. Numbers contains one empty table,
Pages contains one empty page, and Keynote contains one empty white slide.
They contain no sample data or premium content. Older iWork versions have not
been verified.

Keep these as single-file ZIP-based native documents, not directory packages:
`NewFileCreator` writes their bytes with exclusive creation to avoid overwriting
an existing file. Open/save replacements in their corresponding app and verify
that renamed copies open correctly before replacing these resources.

After preparing or verifying a template, close its `Blank` document window before
quitting the iWork app. Otherwise that test window may remain open or be restored
alongside the first `Untitled` document, misleading users into thinking creation
opened two files. For first-open checks, use copies in `build/`, verify each app's
Window menu contains only the requested document, then close the test document.
The product creation path only writes one file and never opens the source template.

The Xcode project copies this folder into the host app. The Finder extension
forwards creation requests to the host so document writes occur outside the
extension sandbox. No Apple Events or iWork installation is needed for creation.
