# Blank document templates

## Office / WPS

`Blank.docx`, `Blank.xlsx`, and `Blank.pptx` are standard, macro-free OOXML
documents generated locally on 2026-10-19. Word contains one empty A4 page,
Excel contains one empty `Sheet1`, and PowerPoint contains one empty white
16:9 slide with no placeholder objects. Creation copies the template bytes;
it does not require Office / WPS or change the user's default file associations.

The Word template was generated with python-docx; the workbook and presentation
were generated with the bundled Artifact Tool. All three have rendered previews
and package checks. `Tests/OfficeTemplateChecks.py` verifies ZIP integrity,
content types, internal relationships, absence of external links/macros, and
the intended empty content. It runs as part of `Scripts/test-features.sh`.
The general presentation validator flags slides without drawable objects;
that is intentional for this blank template and is checked explicitly here.

Local WPS opening checks passed for all three formats on 2026-10-19: one blank
page, one empty worksheet, and one blank slide, with no repair prompts. The Word
template uses Arial / PingFang SC and the workbook uses Arial to avoid missing
default fonts on macOS. Native Microsoft Office opening and editing have not
been verified on this machine. WPS was in guest mode, so editing/save round trips
were not verified there.

## Apple iWork

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
