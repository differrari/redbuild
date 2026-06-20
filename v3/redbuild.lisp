(load "~/quicklisp/setup.lisp")
(ql:quickload :uiop)

;;;;;
(defmacro println (&rest args) 
    `(progn 
        (format t "~&~{~a~^ ~}~&" (list ,@args))))
(defun printlist (lst) (format t "~&~{~a~&~}~&" lst))
;;;;;


;;;;;
(defparameter *project_root_folder* (user-homedir-pathname))

(defun resolve_path (path) (concatenate `string *project_root_folder* path))

(deftype environments () '(member :redacted :linux :mac :windows))
(defun native ()
    (if (uiop:os-windows-p) :windows 
        (if (uiop:os-unix-p) :linux
            (if (uiop:os-macosx-p) :mac
                :redacted)
        )
    )
)

(defparameter *current_env* :linux)

(defun resolve_compiler (environment comp_name) 
    (case environment 
        (:redacted (concatenate `string "aarch64-none-elf-" comp_name))
        (:linux (concatenate `string "" comp_name))
        (:mac (concatenate `string "" comp_name))
        (:windows (concatenate `string "" comp_name))
        (otherwise (error "Unknown environment type ~S" environment))
    )
)
;;;;;;

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
(defun lib-to-include (lib) (let ((inc (lib-include lib))) (if (eq (length inc) 0) nil (concatenate `string "-I" inc))))

(defun local_lib (name &key (path *project_root_folder*) (lib (format nil "lib~a.a" name)) (subpath "")) 
    (make-instance `lib_class
        :header_include (format nil "~a~a" path name)
        :source_include (format nil "~a~a~a/~a" path name subpath lib)
    )
)

(defun system_lib (name) 
    (make-instance `lib_class
        :header_include ""
        :source_include (format nil "-l~a" name)
    )
)

(defun system_fw (name) 
    (make-instance `lib_class
        :header_include ""
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

(defmacro redlib (targ) (local_lib "redlib" :lib           (case targ (:redacted "libshared.a") (otherwise "clibshared.a"))))
(defmacro glfw (type targ) (case type (:bin ()) (otherwise (case targ (:redacted ()) (otherwise (system_lib "glfw"))))))
(defmacro libc (type targ) (case type (:bin ()) (otherwise (case targ (:redacted ()) (otherwise (system_lib "c"))))))
(defmacro libm (type targ) (case type (:bin ()) (otherwise (case targ (:redacted ()) (otherwise (system_lib "m"))))))
(defun default_dependencies (type targ) (list (redlib targ) (libc type targ) (libm type targ)))

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
        (target
            :initarg :target
            :type environments
            :accessor redmod-target)
        (libraries
            :initarg :libs
            :type list
            :initform ()
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
            :initform ()
            :documentation "compiler and linker flags"
            :accessor redmod-flags)
    )
)

(defclass comp_cmd () 
    (
        (filen
            :initarg :file-name
            :type string
            :initform ""
            :accessor cc-file-name)
        (dir
            :initarg :dir
            :type string
            :initform ""
            :accessor cc-dir)
        (out
            :initarg :out
            :type string
            :initform ""
            :accessor cc-out)
        (cmds
            :initarg :cmds
            :type list
            :initform ()
            :accessor cc-cmds)
    )
)

(defgeneric flatten-args (lst));TODO: probably better off to use (flatten lst) instead in most places, and can make it generic too

(defmethod flatten-args ((lst list)) (format nil "~{~A~^ ~}" lst))
(defmethod flatten-args ((lst string)) (format nil "~a" lst))

(defun flatten (lst)
    (cond ((null lst) nil)
        ((atom lst) (list lst))
        (t (append (flatten (car lst)) (flatten (cdr lst))))
    )
)

(defun make-command (mod) (mapcar #'flatten-args (remove nil (list 
    (resolve_compiler *current_env* *compiler*)
    (redmod-flags mod)
    (remove nil (mapcar #'lib-to-include (redmod-libraries mod)))
    (redmod-sources mod) 
    (mapcar #'lib-source (redmod-libraries mod))
    "-o" 
    (concatenate `string (redmod-name mod) (output_type_name mod))
))))

(defun run_prog (cmd) (nth-value 2 (uiop:run-program cmd :ignore-error-status t :error-output t)))

(defun replace-extension (path newext) 
    (namestring (make-pathname :type newext :defaults (pathname path))))

(defun lib-command-list (includes src) (list "gcc" includes "-c" src "-o" (replace-extension src "o")))

(defun lib-command (includes src) (uiop:run-program (lib-command-list includes src)) :output t)

(defun lib-assemble-list (srcs output) (flatten (list "ar" "rcs" output srcs)))

(defun lib-assemble (srcs output) (nth-value 2 (uiop:run-program (lib-assemble-list srcs output) :error-output t)));;TODO: This gets rid of output

(defun lib-compile (mod) 
    (let ((libs (flatten-args (remove nil (mapcar #'lib-to-include (redmod-libraries mod))))))
        (mapcar (lambda (a) (lib-command libs a)) (redmod-sources mod))
        (lib-assemble (redmod-sources mod) (concatenate `string (redmod-name mod) (output_type_name mod)))
    )
)

(defun lib-compile-cc (mod) 
    (let ((libs (flatten-args (remove nil (mapcar #'lib-to-include (redmod-libraries mod))))))
        (append
            (mapcar (lambda (a) 
                (make-instance `comp_cmd 
                    :file-name a
                    :out (replace-extension a "o")
                    :cmds (flatten (lib-command-list libs a))
                )
            ) (redmod-sources mod))
            (list (make-instance `comp_cmd 
                :file-name (first (redmod-sources mod))
                :out (concatenate `string (redmod-name mod) (output_type_name mod))
                :cmds (lib-assemble-list (redmod-sources mod) (concatenate `string (redmod-name mod) (output_type_name mod)))
            ))
        )
    )
)

(defun redb_compile (mod &key success fail) "Compile a redbuild module"
    (print "Beginning compilation")
    (case (redmod-type mod)
        (:lib (if (= (lib-compile mod) 0) 
            (funcall success) 
            (funcall fail)
            )
        )
        (otherwise (if (= (run_prog (flatten-args (make-command mod))) 0) 
            (funcall success) 
            (funcall fail)
            )
        )
    )
)

(defun redb_run (mod)
    (let ((namee (redmod-name mod)))
        (uiop:run-program (list "chmod" "+x" (concatenate `string namee (output_type_name mod))))
        (format t "~&=====~a=====~&" namee)
        (uiop:run-program (concatenate `string "./" namee (output_type_name mod)) :ignore-error-status t :output t)
        (format t "~&=====~a=====~&" (make-string (length namee) :initial-element #\=))
    )
)

(defparameter *compcmds* '())

(defun redb_compile_commands (mod &key) "Generate a redbuild module's compile_commands.json file"
    (setf *compcmds* (append *compcmds* (case (redmod-type mod)
        (:lib (lib-compile-cc mod))
        (otherwise (list (make-instance `comp_cmd 
            :cmds (make-command mod) 
            :file-name (first (redmod-sources mod))
            :out (concatenate `string (redmod-name mod) (output_type_name mod))
        )))
    )))
)

(defun formatcc (cclist)
    (format nil "  \"arguments\":[~&~{      \"~a\"~^,~&~}~&  ],~&  \"output\":\"~a\",~&  \"file\":\"~a\",~&  \"directory\":\"~a\"~&" (cc-cmds cclist) (cc-out cclist) (cc-file-name cclist) (uiop:getcwd))
)

(defun formatmod (str into)
    (format into "{")
)

(defun emit_compile_commands () (print "Emitting compile commands") 
    (with-open-file (stream #p"compile_commands.json" :direction :output :if-exists :supersede)
        (format stream "[")
        (format stream "~{{~&~a}~^,~&~}" (mapcar #'formatcc *compcmds*))
        (format stream "]")
    )
)

(defun redb_fallback (mod &key) "Generate a redbuild module fallback simplemake file for compilation with other build systems"
    (with-open-file (stream #p"simplemake" :direction :output :if-exists :supersede)
        (format stream "~&~{~a~&~}~&" (redmod-sources mod))
    )
)

(defun quick_redb (mod &key add-dependencies run success fail) 
    (if (eq add-dependencies t) (setf (redmod-libraries mod) (default_dependencies (redmod-type mod) (redmod-target mod))))
    (redb_compile mod 
        :success (lambda () 
            (redb_fallback mod)
            (redb_compile_commands mod)
            (if (and (not (eq :lib (redmod-type mod))) (eq run t)) (redb_run mod))
            (funcall success) 
        ) 
        :fail (lambda () (format t "Compilation failed for ~a" (redmod-name mod)))
    )
)