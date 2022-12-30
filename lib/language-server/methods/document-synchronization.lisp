(in-package :lem-language-server)

(defclass text-document ()
  ((uri :initarg :uri :accessor text-document-uri)
   (language-id :initarg :language-id :accessor text-document-language-id)
   (version :initarg :version :accessor text-document-version)
   (buffer :initarg :buffer :accessor text-document-buffer)))

(defmethod print-object ((object text-document) stream)
  (print-unreadable-object (object stream :type t)
    (format stream "uri:~S version:~A" (text-document-uri object) (text-document-version object))))

(defvar *text-document-table* (make-hash-table :test 'equal))

(defun register-text-document (text-document)
  (setf (gethash (text-document-uri text-document) *text-document-table*)
        text-document))

(defun find-text-document (text-document-identifier)
  (check-type text-document-identifier
              protocol:text-document-identifier)
  (gethash (protocol:text-document-identifier-uri text-document-identifier)
           *text-document-table*))

(defun close-text-document (text-document)
  (check-type text-document text-document)
  (lem:delete-buffer (text-document-buffer text-document))
  (remhash (text-document-uri text-document)
           *text-document-table*))

(defun move-to-lsp-position (point position)
  (check-type point lem:point)
  (check-type position protocol:position)
  (let ((line (protocol:position-line position))
        (character (protocol:position-character position)))
    (lem:move-to-line point (1+ line))
    (lem:character-offset (lem:line-start point) character)
    point))

(defun edit-text-document (text-document content-change)
  (check-type text-document text-document)
  (check-type content-change protocol:text-document-content-change-event)
  (let* ((buffer (text-document-buffer text-document))
         (point (lem:buffer-point buffer))
         (text (gethash "text" content-change))
         (range (gethash "range" content-change)))
    (log:info range text)
    (cond ((null range)
           (lem:erase-buffer buffer)
           (lem:insert-string point text))
          (t
           (let ((start-position (protocol:range-start range))
                 (end-position (protocol:range-end range)))
             (lem:with-point ((start point)
                              (end point))
               (move-to-lsp-position start start-position)
               (move-to-lsp-position end end-position)
               (lem:delete-between-points start end)
               (lem:insert-string start text)))))))

(define-request (text-document-did-open "textDocument/didOpen")
    (params protocol:did-open-text-document-params)
  (with-accessors ((item protocol:did-open-text-document-params-text-document))
      params
    (with-accessors ((uri protocol:text-document-item-uri)
                     (language-id protocol:text-document-item-language-id)
                     (version protocol:text-document-item-version)
                     (text protocol:text-document-item-text))
        item
      (log:info "textDocument/didOpen" uri language-id version)
      (let ((buffer (lem:make-buffer (format nil "*lsp-server ~A ~A*" uri version)
                                     :enable-undo-p nil
                                     :syntax-table lem-lisp-syntax:*syntax-table*)))
        (lem:insert-string (lem:buffer-point buffer) text)
        (register-text-document (make-instance 'text-document
                                               :uri uri
                                               :language-id language-id
                                               :version version
                                               :buffer buffer)))
      (values))))

(define-request (text-document-did-change "textDocument/didChange")
    (params protocol:did-change-text-document-params)
  (with-accessors ((text-document-identifier protocol:did-change-text-document-params-text-document)
                   (content-changes protocol:did-change-text-document-params-content-changes))
      params
    (let ((text-document (find-text-document text-document-identifier)))
      (log:info "textDocument/didChange" text-document)
      (lem:do-sequence (content-change content-changes)
        (edit-text-document text-document content-change))))
  (values))

;; TODO
(define-request (text-document-will-save "textDocument/willSave")
    (params protocol:will-save-text-document-params)
  (declare (ignore params))
  (log:info "textDocument/willSave"))

;; TODO
(define-request (text-document-will-save-wait-until "textDocument/willSaveWaitUntil")
    (params protocol:will-save-text-document-params)
  (declare (ignore params))
  (log:info "textDocument/willSaveWaitUntil"))

;; TODO
(define-request (text-document-did-save "textDocument/didSave")
    (params protocol:did-save-text-document-params)
  (declare (ignore params))
  (log:info "textDocument/didSave"))

(define-request (text-document-did-close "textDocument/didClose")
    (params protocol:did-close-text-document-params)
  (with-accessors ((text-document-identifier protocol:did-close-text-document-params-text-document))
      params
    (let ((text-document (find-text-document text-document-identifier)))
      (log:info "textDocument/didClose" text-document)
      (close-text-document text-document)))
  (values))