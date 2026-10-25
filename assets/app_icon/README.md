# App icon assets

The supplied artwork was adapted to a full-bleed square background. The original image remains untouched.

- `master.png`: editable source for generating sizes.
- `app-store-1024.png`: 1024×1024 RGB PNG, without alpha or pre-rounded corners.
- `google-play-512.png`: 512×512 RGBA PNG, fully opaque, under 1 MB.

The iOS asset catalog and Android launcher mipmaps use these assets. From the repository root, regenerate with `swift tool/generate_app_icons.swift` (macOS with Xcode).

Specifications:
- https://developer.apple.com/documentation/xcode/configuring-your-app-icon
- https://developer.android.com/distribute/google-play/resources/icon-design-specifications

Store listing assets must be uploaded in their respective store consoles. These exports do not constitute store submission or approval.
