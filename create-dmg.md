create-dmg 1.2.3

Creates a fancy DMG file.

Usage:  create-dmg [options] <output_name.dmg> <source_folder>

All contents of <source_folder> will be copied into the disk image.

Options:
  --volname <name>
      set volume name (displayed in the Finder sidebar and window title)
  --volicon <icon.icns>
      set volume icon
  --background <pic.png>
      set folder background image (provide png, gif, or jpg)
  --window-pos <x> <y>
      set position the folder window
  --window-size <width> <height>
      set size of the folder window
  --text-size <text_size>
      set window text size (10-16)
  --icon-size <icon_size>
      set window icons size (up to 128)
  --icon file_name <x> <y>
      set position of the file's icon
  --hide-extension <file_name>
      hide the extension of file
  --app-drop-link <x> <y>
      make a drop link to Applications, at location x,y
  --ql-drop-link <x> <y>
      make a drop link to user QuickLook install dir, at location x,y
  --eula <eula_file>
      attach a license file to the dmg (plain text or RTF)
  --no-internet-enable
      disable automatic mount & copy
  --format <format>
      specify the final disk image format (UDZO|UDBZ|ULFO|ULMO) (default is UDZO)
  --filesystem <filesystem>
      specify the disk image filesystem (HFS+|APFS) (default is HFS+, APFS supports macOS 10.13 or newer)
  --encrypt
      enable encryption for the resulting disk image (AES-256 - you will be prompted for password)
  --encrypt-aes128
      enable encryption for the resulting disk image (AES-128 - you will be prompted for password)
  --add-file <target_name> <file>|<folder> <x> <y>
      add additional file or folder (can be used multiple times)
  --disk-image-size <x>
      set the disk image size manually to x MB
  --hdiutil-verbose
      execute hdiutil in verbose mode
  --hdiutil-quiet
      execute hdiutil in quiet mode
  --hdiutil-retries <x>
      specify the number of retries for the "Resource busy" error from "hdiutil create" and "hdiutil detach" (default is 5)
  --bless
      bless the mount folder (deprecated, needs macOS 12.2.1 or older)
  --codesign <signature>
      codesign the disk image with the specified signature
  --notarize <credentials>
      notarize the disk image (waits and staples) with the keychain stored credentials
  --sandbox-safe
      execute hdiutil with sandbox compatibility and do not bless (not supported for APFS disk images)
  --skip-jenkins
      skip Finder-prettifying AppleScript, useful in Sandbox and non-GUI environments
  --version
	    show create-dmg version number
  -h, --help
	    display this help screen

        