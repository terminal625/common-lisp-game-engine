(asdf:defsystem #:testbed
  :depends-on (#:application
	       #:sandbox
	       #:opticl
	       #:reverse-array-iterator
	       #:singleton-lparallel)
  :serial t
  :components 
  ((:file "struct-to-clos")
   (:file "aabbcc")
   (:file "sandbox-subsystem")
   (:file "testbed")))