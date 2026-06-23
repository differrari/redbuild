(load "../v3/redbuild.lisp")
(load "~/redlisp/utils.lisp")

(defparameter *root* (namestring (uiop:getcwd)))
(defparameter *staging-area* (concatenate `string *root* "staging"))
(defparameter *template-area* (concatenate `string *root* "templates"))
(defparameter *input-area* (concatenate `string *root* "input"))

(defun get-folder-for-type (type) (case type 
    (:redacted "Redacted")
    (:linux "AppImage")
    (:mac "MacApp")
    (:windows "Windows")
    (otherwise (error "Unknown environment type ~S" type))
))

(defun get-template-dir (type) (concatenate `string *template-area* "/" (get-folder-for-type type)))
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

(defun copy-dir (name)
    (uiop:run-program (list "cp" "-r" (get-input name) (namestring (uiop:getcwd))))
)

(defun copy-file (name)
    (uiop:run-program (list "cp" (get-input name) (namestring (uiop:getcwd))))
)

(defun load-template (type name)
     (uiop:read-file-string (concatenate `string (get-template-dir type) "/" name))
)

(defun redpkg (name)
    (make-dir (concatenate `string name ".red") 
        (make-file "package.info" (load-template :redacted "package.info"))
        (copy-dir "resources")
        (copy-file (concatenate `string name ".elf"))
    )
)

(defun macpkg (name)
    (make-dir (concatenate `string name ".app") 
        (make-dir "Contents" 
            (make-file "Info.plist" (load-template :mac "Info.plist"))
            (make-dir "Resources" 
                (copy-dir "resources")
            ) 
            (make-dir "MacOS" 
                (copy-file name)
            )
        )
    )
)

(defun generate-build (name environment) 
    ; clear the staging area
    ; check for presence of a resources folder (optional), config and executable
    (uiop:chdir (concatenate `string *root* "staging"))
    (case environment 
        (:redacted (redpkg name))
        (:linux (error "Packaging for ~S not implemented yet" environment))
        (:mac (macpkg name))
        (:windows (error "Packaging for ~S not implemented yet" environment))
        (otherwise (error "Unknown environment type ~S" environment))
    )
)

(generate-build "ghost" :mac)