(asdf:defsystem #:minisucle
  :author "terminal625"
  :license "MIT"
  :description "Cube Demo Game"
  :depends-on
  (#:sucle-base
   #:alexandria  
   #:utility

   #:sucle-base
   #:aabbcc ;;for occlusion culling 
   #:livesupport)
  :serial t
  :components 
  (
   
   
   (:file "package")
   (:file "util")
   (:file "menu")
   (:file "menus")
   (:file "physics")
   (:file "sucle")
   (:file "render")))