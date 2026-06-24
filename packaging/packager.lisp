(load "../v3/redbuild.lisp")
(load "~/redlisp/utils.lisp")
(load "common.lisp")
(load "templates.lisp")

(defparameter *root* (namestring (uiop:getcwd)))
(defparameter *staging-area* (concatenate `string *root* "staging"))
(defparameter *input-area* (concatenate `string *root* "input"))

(defun get-folder-for-type (type) (case type 
    (:redacted "Redacted")
    (:linux "AppImage")
    (:mac "MacApp")
    (:windows "Windows")
    (otherwise (error "Unknown environment type ~S" type))
))

(defun get-input (name) (concatenate `string *input-area* "/" name))

(defun absolute-pathname (name) (merge-pathnames (uiop:getcwd) (make-pathname :name name)))
(defun absolute-pathstring (name) (namestring (absolute-pathname name)))

(defun make-file (name source)
    (with-open-file (stream (merge-pathnames (uiop:getcwd) (make-pathname :name name)) :direction :output :if-exists :supersede)
        (format stream source)
    )
)

(defmacro make-dir (name &body body)
    `(progn 
        (let ((old_name (uiop:getcwd)))
        (uiop:run-program (list "mkdir" "-p" ,name))
        (uiop:chdir ,name)
        ,@body
        (uiop:chdir old_name)
        )
    )
)

(defun copy-dir (name &key (can-fail nil))
    (uiop:run-program (list "cp" "-r" (get-input name) (namestring (uiop:getcwd))) :ignore-error-status can-fail)
)

(defun copy-file (name &key (can-fail nil) (destination-name name))
    (uiop:run-program (list "cp" (get-input name) (concatenate `string (namestring (uiop:getcwd)) "/" destination-name)) :ignore-error-status can-fail)
)

(defun redpkg (pkg)
    (make-dir (concatenate `string (pack-name pkg) ".red") 
        (make-file "package.info" (redacted-package-info pkg))
        (copy-dir "resources" :can-fail t)
        (copy-file (concatenate `string (pack-name pkg) ".elf"))
    )
)

(defun macpkg (pkg)
    (make-dir (concatenate `string (pack-name pkg) ".app") 
        (make-dir "Contents" 
            (make-file "Info.plist" (apple-info-plist pkg))
            (make-dir "Resources" 
                (copy-dir "resources")
            ) 
            (make-dir "MacOS" 
                (copy-file (concatenate `string (pack-name pkg) ".elf") :destination-name (pack-name pkg))
            )
        )
    )
)

(defun clean-staging () (uiop:delete-directory-tree (make-pathname :directory *staging-area*) :validate t :if-does-not-exist :ignore))

(defun generate-build (pkg environment &key (clean t)) 
    (if clean (clean-staging))
    (make-dir "staging"
        (case environment 
            (:redacted (redpkg pkg))
            (:linux (error "Packaging for ~S not implemented yet" environment))
            (:mac (macpkg pkg))
            (:windows (error "Packaging for ~S not implemented yet" environment))
            (otherwise (error "Unknown environment type ~S" environment))
        )
    )
)