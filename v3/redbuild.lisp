(load "~/quicklisp/setup.lisp")
(ql:quickload :uiop)

(defpackage :redbuild
  (:use :common-lisp :uiop/package)
  (:export
      #:dynlib
      #:dynsrc
      #:set-tester
      #:quick-build
      #:fallback 
      #:emit-compile-commands 
      #:compile-commands 
      #:run 
      #:compile-module
      #:make-instance
      #:make
      #:build-dep
      #:redmod 
      #:local-lib 
      #:system-lib 
      #:system-fw 
      #:environments 
      #:native 
      #:dyn-target
      #:set-global-target
      #:resolve-compiler
      #:default-dependencies
      #:quick-cred
      #:all-sources
      #:all-sources-ignoring
      #:install
    )
)

(in-package :redbuild)

(defparameter *root-folder* (user-homedir-pathname))

(deftype environments () '(member :redacted :linux :mac :windows))
(defun native ()
    (cond 
        ((uiop:os-windows-p) :windows)
        ((uiop:os-macosx-p) :mac)
        ((uiop:os-unix-p) :linux)
        (t :redacted)
    )
)

(defvar *global-target* nil)

(defun set-global-target (type) "Set a global target to compile all dependencies that use dyn-target against"
    (if (eq *global-target* nil) (setf *global-target* type))
)

(defun dyn-target () "Compile to the current system unless global-target is set"
    (cond 
        ((not (eq *global-target* nil)) *global-target*)
        (t (native))
    )
)

(defun resolve-compiler (environment compiler-name) 
    (case environment 
        (:redacted (concatenate `string "aarch64-none-elf-" compiler-name))
        (:linux (concatenate `string "" compiler-name))
        (:mac (concatenate `string "" compiler-name))
        (:windows (concatenate `string "" compiler-name))
        (otherwise (error "Unknown environment type ~S" compiler-name))
    )
)
;;;;;;

(defclass lib-class () 
    (
        (header 
            :initarg :header
            :type string
            :accessor lib-include)
        (source 
            :initarg :source
            :type string
            :accessor lib-source)
    )
)
(defun lib-to-include (l) 
    (cond 
        ((eq l nil) nil) 
        (t 
            (let ((inc (lib-include l)))
                (if (eq (length inc) 0) 
                    nil 
                (concatenate `string "-I" inc)
                )
            )
        )
    )
)

(defun local-lib (name &key (path *root-folder*) (lib (format nil "lib~a.a" name)) (subpath "")) 
    (make-instance `lib-class
        :header 
        (cond 
            ((or (string= name "") (eq name "")) ".")
            (t (format nil "~a~a" path name))
        )
        :source (cond 
            ((or (string= name "") (eq name "")) nil)
            (t (format nil "~a~a~a/~a" path name subpath lib))
        )
    )
)

(defun install (src &key (location (concatenate `string (uiop:getenv "HOME") "/os_repo/applications/")))
    (uiop:run-program (list "cp" "-r" src location) :output t :error-output t)
)

(defun system-lib (name) 
    (make-instance `lib-class
        :header ""
        :source (format nil "-l~a" name)
    )
)

(defun system-fw (name) 
    (make-instance `lib-class
        :header ""
        :source (list "-framework" name)
    )
)

(defun link-targ (p inc-path link-path) 
    (make-instance `lib-class
        :header (format nil "~a/~a" p inc-path)
        :source (format nil "-L~a/~a" p link-path)
    )
)

(defparameter *compiler* "gcc")

(deftype output-type () `(member :lib :bin :red))
(defun output-type-name (type) 
    (case (redmod-type type)
        (:lib ".a")
        (:bin ".elf")
        (:red ".elf")
        (otherwise (error "Unknown output type ~S" (redmod-type type)))
    )
)

(defun redlib (targ) (local-lib "redlib" :lib           (case targ (:redacted "libshared.a") (otherwise "clibshared.a"))))
(defun glfw (type targ) (case type (:lib ()) (otherwise (case targ (:redacted ()) (otherwise (system-lib "glfw"))))))
(defun gl   (type targ) (case type (:lib ()) (otherwise (case targ (:redacted ()) (:mac (system-fw "OpenGL")) (otherwise (system-lib "GL"))))))
(defun libc (type targ) (case type (:lib ()) (otherwise (case targ (:redacted ()) (otherwise (system-lib "c"))))))
(defun libm (type targ) (case type (:lib ()) (otherwise (case targ (:redacted ()) (otherwise (system-lib "m"))))))
(defun default-dependencies (type targ) (list (if (eq targ :mac) (link-targ "/opt/homebrew" "include" "lib") ()) (local-lib "" :path (uiop:getcwd) :lib "") (redlib targ) (glfw type targ) (libc type targ) (libm type targ) (gl type targ)))

(defclass redmod () 
    (
        (name
            :initarg :name
            :type string
            :accessor redmod-name)
        (type
            :initarg :type
            :type output-type
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

(defclass comp-cmd () 
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

(defun flatten (lst)
    (cond
        ((null lst) nil)
        ((atom lst) (list lst))
        (t (append (flatten (car lst)) (flatten (cdr lst))))
    )
)

(defun make-command (mod) (flatten (remove nil (list 
    (resolve-compiler (redmod-target mod) *compiler*)
    "-std=c99"
    (if (eq (redmod-target mod) :redacted) (list "-Wl,-emain" "-ffreestanding" "-nostdlib"))
    (redmod-flags mod)
    (remove nil (mapcar #'lib-to-include (redmod-libraries mod)))
    (redmod-sources mod) 
    (mapcar #'lib-source (remove nil (redmod-libraries mod)))
    "-o" 
    (concatenate `string (redmod-name mod) (output-type-name mod))
))))

(defun run-prog (cmd) (nth-value 2 (uiop:run-program (flatten cmd) :ignore-error-status t :error-output t)))

(defun replace-extension (path newext) 
    (namestring (make-pathname :type newext :defaults (pathname path))))

(defun lib-command-list (mod includes src) (flatten (list (resolve-compiler (redmod-target mod) *compiler*) "-std=c99" includes "-c" src "-o" (replace-extension src "o"))))

(defun lib-command (mod includes src) (uiop:run-program (lib-command-list mod includes src) :ignore-error-status t :error-output t))

(defun lib-assemble-list (mod srcs output) (flatten (list (resolve-compiler (redmod-target mod) "ar") "rcs" output (mapcar (lambda (a) (replace-extension a "o")) srcs))))

(defun lib-assemble (mod srcs output) (nth-value 2 (uiop:run-program (lib-assemble-list mod srcs output) :ignore-error-status t :error-output t)))

(defun lib-compile (mod) 
    (let ((libs (flatten (remove nil (mapcar #'lib-to-include (redmod-libraries mod))))))
        (mapcar (lambda (a) (lib-command mod libs a)) (redmod-sources mod))
        (lib-assemble mod (redmod-sources mod) (concatenate `string (redmod-name mod) (output-type-name mod)))
    )
)

(defun lib-compile-cc (mod) 
    (let ((libs (flatten (remove nil (mapcar #'lib-to-include (redmod-libraries mod))))))
        (append
            (mapcar (lambda (a) 
                (make-instance `comp-cmd 
                    :file-name a
                    :out (replace-extension a "o")
                    :cmds (flatten (lib-command-list mod libs a))
                )
            ) (redmod-sources mod))
            (list (make-instance `comp-cmd 
                :file-name (first (redmod-sources mod))
                :out (concatenate `string (redmod-name mod) (output-type-name mod))
                :cmds (lib-assemble-list mod (redmod-sources mod) (concatenate `string (redmod-name mod) (output-type-name mod)))
            ))
        )
    )
)

(defun compile-module (mod &key success fail) "Compile a redbuild module"
    (print "Beginning compilation")
    (case (redmod-type mod)
        (:lib (if (= (lib-compile mod) 0) 
            (funcall success) 
            (funcall fail)
            )
        )
        (otherwise (if (= (run-prog (flatten (make-command mod))) 0) 
            (funcall success) 
            (funcall fail)
            )
        )
    )
)

(defun run (mod &key (args nil)) "Run the executable of a redbuild module"
    (let ((namee (redmod-name mod)))
        (uiop:run-program (list "chmod" "+x" (concatenate `string namee (output-type-name mod))))
        (format t "~&=====~a=====~&" namee)
        (uiop:run-program (flatten (list (concatenate `string "./" namee (output-type-name mod)) args)) :ignore-error-status nil :output t :error-output t)
        (format t "~&=====~a=====~&" (make-string (length namee) :initial-element #\=))
    )
)

(defparameter *compcmds* '())

(defun compile-commands (mod) "Generate a redbuild module's compile_commands.json file. Will need to call emit-compile-commands to produce the final file"
    (setf *compcmds* (append *compcmds* (case (redmod-type mod)
        (:lib (lib-compile-cc mod))
        (otherwise (list (make-instance `comp-cmd 
            :cmds (make-command mod) 
            :file-name (first (redmod-sources mod))
            :out (concatenate `string (redmod-name mod) (output-type-name mod))
        )))
    )))
)

(defun formatcc (cclist)
    (format nil "  \"arguments\":[~&~{      \"~a\"~^,~&~}~&  ],~&  \"output\":\"~a\",~&  \"file\":\"~a\",~&  \"directory\":\"~a\"~&" (cc-cmds cclist) (cc-out cclist) (cc-file-name cclist) (uiop:getcwd))
)

(defun emit-compile-commands () "Emit a compile_commands.json file" 
    (with-open-file (stream #p"compile_commands.json" :direction :output :if-exists :supersede)
        (format stream "[")
        (format stream "~{{~&~a}~^,~&~}" (mapcar #'formatcc *compcmds*))
        (format stream "]")
    )
    (setf *compcmds* '())
)

(defmacro make (path &rest args) 
    `(uiop:run-program (list "make" "-C" ,path ,@args) :output t :error-output t)
)

(defmacro tmp-switch-dir (name &body body)
    `(progn 
        (let ((old_name (uiop:getcwd)))
        (uiop:chdir ,name)
        (print (uiop:getcwd))
        ,@body
        (uiop:chdir old_name)
        )
    )
)

(defun build-dep (path)
    (tmp-switch-dir path
        (load (concatenate `string path "/build.lisp"))
    )
)

(defun fallback (mod) "Generate a redbuild module fallback simplemake file for compilation with other build systems"
    (with-open-file (stream #p"simplemake" :direction :output :if-exists :supersede)
        (format stream "~&# Compile these files against glfw, libc, libm and https://github.com/differrari/redlib/")
        (format stream "~&# or use using https://github.com/differrari/redbuild/blob/main/Simplemakefile")
        (format stream "~&~{~a~&~}~&" (redmod-sources mod))
    )
)

(defun quick-build (mod &key add-dependencies (debug-symbols t) run success fail (run-args nil)) "Quick redbuild project compilation"
    (if (eq add-dependencies t) (setf (redmod-libraries mod) (concatenate `list (redmod-libraries mod) (default-dependencies (redmod-type mod) (redmod-target mod)))))
    (if (eq debug-symbols t) (setf (redmod-flags mod) (concatenate `list (list "-g") (redmod-flags mod))))
    (mapcar #'print (cc-cmds (car (redbuild:compile-commands mod))))
    (compile-module mod 
        :success (lambda () 
            (fallback mod)
            (compile-commands mod)
            (if (and (not (eq :lib (redmod-type mod))) (eq run t)) (run mod :args run-args))
            (if (not (eq success nil)) (funcall success))
        ) 
        :fail (lambda () (format t "Compilation failed for ~a" (redmod-name mod)))
    )
)

(defun quick-cred (input-file output-file) (nth-value 2 (uiop:run-program (list "cred" input-file "-o" output-file) :output t :error-output t)))

;;; test lib as binary ;;;
(defparameter *tester-file* nil)
(defmacro dynlib () (if *tester-file* :bin :lib))
(defmacro dynsrc (&rest libfiles) `(remove nil (append (list ,@libfiles) (list *tester-file*))))

(defun set-tester (name) "Call this function with a filename containing a main function to turn a library into a binary and test it using that tester file. Use dynlib and dynsrc macros to make the changes" (setf *tester-file* name))

(defun last-path-component (path) (first (last (pathname-directory path))))
(defun is-dot-f (path) (eq (char (file-namestring path) 0) #\.))
(defun is-dot-d (path) (eq (char (last-path-component path) 0) #\.))

(defun all-sources-in-dir (d extension) 
    (list 
        (remove-if-not
            (lambda (f) (string= extension (pathname-type f))) 
            (remove-if #'is-dot-f (uiop:directory-files d))
        )
        (mapcar (lambda (sd) (all-sources-in-dir sd extension)) (remove-if #'is-dot-d (uiop:subdirectories d)))
    )
)

(defun all-sources (extension) (mapcar #'namestring (flatten (all-sources-in-dir (uiop:getcwd) extension))))

(defmacro all-sources-ignoring (extension lst)
   `(remove-if (lambda (s) (member (file-namestring s) ,lst :test #'string-equal)) (redbuild:all-sources ,extension))
)
