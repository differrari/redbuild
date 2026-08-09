(defclass pack () (
    (name
        :initarg :name
        :type string
        :accessor pack-name)
    (exec
        :initarg :exec
        :type string
        :accessor pack-exec)
    (author
        :initarg :author
        :type string
        :initform ""
        :accessor pack-author)
    (version
        :initarg :version
        :type string
        :initform ""
        :accessor pack-version)
    (categories
        :initarg :categories
        :type string
        :initform ""
        :accessor pack-categories)
    (id
        :initarg :id
        :type string
        :initform ""
        :accessor pack-id
    )
))