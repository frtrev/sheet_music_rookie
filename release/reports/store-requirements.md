# Official store requirements verified 6 November 2026

## Apple

Source: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/

The current page requires a medium Dynamic Island iPhone screenshot and, for this iPad-enabled build, 13-inch iPad screenshots. This differs from older 6.9-inch-only checklists. Large Dynamic Island iPhone screenshots are also supplied for the requested large-screen category. Apple accepts 1–10 screenshots per device size and disallows alpha. The explicit capture choices in scripts/store_targets.json are 1206×2622, 1320×2868, and 2064×2752, all portrait. Other accepted sizes exist; the automation intentionally chooses exactly one native resolution per target slot. Do not upload a large iPhone file into a medium slot.

App Store Connect scales supported classes where allowed; additional legacy iPhone groups are not generated because this app has a consistent UI and the required medium/large groups are supplied. iPhone Duo becomes required starting April 2027 for iOS 27.1+ SDK builds; this preparation is before that date. Refresh the configuration if submitting under changed requirements.

Source: https://developer.apple.com/news/upcoming-requirements/?id=04282026a

Uploads require Xcode 26+ and iOS/iPadOS SDK 26+ since 28 April 2026. Installed Xcode 27.0 with iOS SDK 27.0 satisfies that toolchain minimum; signing/account eligibility is a separate gate. The iOS 15 deployment target is retained.

Source: https://developer.apple.com/app-store/product-page/

Name/subtitle maximum 30 characters, promotional text 170, keywords 100, description 4000. Generated text is checked programmatically. No in-app purchase/subscription assets are required by implemented functionality.

## Google

Source: https://support.google.com/googleplay/android-developer/answer/9866151?hl=en

Screenshots use opaque RGB PNG, each edge 320–3840 pixels and long edge at most twice short edge. Play requires at least two screenshots across device types and allows up to eight per type. This package targets six per supported phone/tablet group. Four or more phone screenshots at 1080×1920 in 9:16 satisfy the documented app promotional-resolution recommendation. Separate ~7 and ~10-inch Android layouts are captured because the manifest does not restrict tablet support. These are not Apple screenshots relabeled for Android.

Google store icon: RGBA PNG, 512×512, at most 1024 KB. Feature graphic: opaque RGB PNG at 1024×500. Existing artwork and app palette are retained. No TV, Wear, automotive, XR, preview video, or other form-factor asset is claimed necessary without matching distribution support/Console selection.

Source: https://support.google.com/googleplay/android-developer/answer/9859152?hl=en

Title 30 characters; short description 80; full description 4000. Store description and title checks are automated. Suggested tags require selection among Console's currently available options.

Source: https://support.google.com/googleplay/android-developer/answer/11926878?hl=en

New apps and updates must target API 36+ since 31 August 2026. This app now explicitly targets 36. Existing-app availability rules are different; they do not replace the new-submission target requirement.

## Scope of validation

Image reports verify exact configured dimensions, PNG structure/CRC, color type/alpha, file size, configured count, expected filenames, unique images and basic nonblank content. Native capture and visual review additionally establish actual app content. Reports cannot guarantee portal account eligibility, future policy stability, trademark/content approval or review acceptance. Check the selected portal slots and distribution devices at submission time.
