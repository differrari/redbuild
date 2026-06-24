(load "~/redlisp/utils.lisp")
(load "common.lisp")

(defmacro multiline (&rest strings)
  `(with-output-to-string (stream)
     ,@(mapcar (lambda (s) `(format stream "~a~&" ,s)) strings)))

(defun prop (fmt var)
    (format nil fmt var)
)

(defun redacted-package-info (pkg) 
    (multiline 
        (prop "app_name=~a" (pack-name pkg))
        (prop "app_version=~a" (pack-version pkg))
        (prop "app_author=~a" (pack-author pkg))
    )
)

(defun appimage-desktop-file (pkg) 
    (multiline 
        "# SPDX-License-Identifier: GPL-2.0-or-later"
        "[Desktop Entry]"
        (prop "Version=~a" (pack-version pkg))
        (prop "Exec=~a" (pack-name pkg))
        "Type=Application"
        (prop "Categories=~a" (pack-categories pkg))
        (prop "Icon=~a.png" (pack-name pkg))
    )
)

(defun appimage-apprun (pkg)
    (multiline
        "#!/bin/sh"
        ""
        "export HERE=\"$(dirname \"$(readlink -f \"${0}\")\")\""
        "export PATH=\"$HERE:$PATH\""
        (prop "\"$HERE/~a\"" (pack-name pkg))
    )
)

(defun apple-info-plist (pkg)
    (multiline 
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
        "<plist version=\"1.0\">"
        "<dict>"
        "   <key>CFBundleDisplayName</key>"
    	(prop "   <string>~a</string>" (pack-name pkg))
    	"   <key>CFBundleExecutable</key>"
    	(prop "   <string>~a</string>" (pack-name pkg))
        "   <key>CFBundleIconFile</key>"
        "   <string>AppIcon-Release</string>"
        "   <key>CFBundleIconName</key>"
        "   <string>AppIcon-Release</string>"
        ; "   <key>CFBundleIdentifier</key>"
        ; (prop " <string>~a</string>" (pack-id pkg))
        "   <key>CFBundleInfoDictionaryVersion</key>"
        "   <string>6.0</string>"
        "   <key>CFBundleName</key>"
        (prop "   <string>~a</string>" (pack-name pkg))
        "   <key>CFBundlePackageType</key>"
        "   <string>APPL</string>"
        "   <key>CFBundleShortVersionString</key>"
        "   <string>2.0</string>"
        "   <key>CFBundleSupportedPlatforms</key>"
        "   <array>"
        "       <string>MacOSX</string>"
        "   </array>"
        "   <key>CFBundleVersion</key>"
        "   <string>103</string>"
        "</dict>"
        "</plist>"
    )
)