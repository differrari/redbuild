;;;;;
(defmacro println (&rest args) 
    `(progn 
        (format t "~&~{~a~^ ~}~&" (list ,@args))))
(defun printlist (lst) (format t "~&~{~a~&~}~&" lst))
;;;;;

(defclass lib_class () 
    (
        (header_include 
            :initarg :header_include
            :type string
            :accessor lib-include)
        (source_include 
            :initarg :source_include
            :type string
            :accessor lib-source)
    )
)
(defun lib-to-include (lib) (concatenate `string "-I" (lib-include lib)))

(defun local_lib (name &key (path "~") (lib (format nil "lib~a.a" name)) (subpath ".")) 
    (make-instance `lib_class
        :header_include (format nil "~a/~a" path name)
        :source_include (format nil "~a/~a/~a/~a" path name subpath lib)
    )
)

(defun system_lib (name) 
    (make-instance `lib_class
        :source_include (format nil "-l~a" name)
    )
)

(defun system_fw (name) 
    (make-instance `lib_class
        :source_include (format nil "-framework ~a" name)
    )
)

(defun add_source (name) (format nil "source: ~a" name))

(defun compile_prog () 
    (print "Going to compile here")
)

(defparameter *compiler* "gcc")

(deftype output_type () `(member :lib :bin :red))
(defun output_type_name (type) 
    (case (redmod-type type)
        (:lib ".a")
        (:bin ".elf")
        (:red ".elf")
        (otherwise (error "Unknown output type ~S" (redmod-type type)))
    )
)

(defclass redmod () 
    (
        (name
            :initarg :name
            :type string
            :accessor redmod-name)
        (type
            :initarg :type
            :type output_type
            :accessor redmod-type)
        (libraries
            :initarg :libs
            :type list
            :documentation "static dependencies"
            :accessor redmod-libraries)
        (sources
            :initarg :srcs
            :type list
            :documentation "c source files"
            :accessor redmod-sources)
        (flags 
            :initarg :flags
            :type list
            :documentation "compiler and linker flags"
            :accessor redmod-flags)
    )
)

(defgeneric flatten-args (lst))

(defmethod flatten-args ((lst list)) (format nil "~{~A~^, ~}" lst))
(defmethod flatten-args ((lst string)) (format nil "~a" lst))

(defun make-command (mod) (mapcar #'flatten-args (list 
    *compiler* 
    (redmod-flags mod)
    (mapcar #'lib-to-include (redmod-libraries mod))
    (redmod-sources mod) 
    (mapcar #'lib-source (redmod-libraries mod))
    "-o" 
    (concatenate `string (redmod-name mod) (output_type_name mod))
)))

(defun redb_compile (mod &key success fail) "Compile a redbuild module"
    (print "Beginning compilation")
    (printlist (make-command mod))
    (if (= 1 1) 
        (funcall success) 
        (funcall fail))
    (print "Compilation is finished")
)

(defun redb_compile_commands (mod &key success fail) "Compile a redbuild module"
    (printlist (make-command mod))
)

(defun redb_fallback (mod &key success fail) "Compile a redbuild module"
    (with-open-file (stream #p"simplemake" :direction :output :if-exists :supersede)
        (format stream "~&~{~a~&~}~&" (redmod-sources mod))
    )
)