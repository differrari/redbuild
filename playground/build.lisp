(load "../v3/redbuild.lisp")

(let 
    ((playground_mod (make-instance `redmod
        :name "play"
        :type :bin
        :libs (list 
            (local_lib "redlib" :path "/home/di" :lib "clibshared.a")
            )
        :srcs (list "test.c")
        :flags (list "-Dtest")
    ))) 
    (redb_compile playground_mod 
        :success (lambda () (redb_fallback playground_mod)) 
        :fail (lambda () (print "Failed"))
    )
)