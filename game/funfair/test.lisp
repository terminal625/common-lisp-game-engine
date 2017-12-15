(defpackage :atest
  (:use :cl
	:funland))
(in-package :atest)
(defparameter *box* #(0 128 0 128 0 128))
(with-unsafe-speed
  (defun map-box (func &optional (box *box*))
    (declare (type (function (fixnum fixnum fixnum)) func)
	     (type simple-vector box))
    (etouq
     (with-vec-params (quote (x0 x1 y0 y1 z0 z1)) (quote (box))
		      (quote (dobox ((x x0 x1)
				     (y y0 y1)
				     (z z0 z1))
				    (funcall func x y z)))))))

(defun grassify (x y z)
  (let ((blockid (world:getblock x y z)))
    (when (= blockid 3)
      (let ((idabove (world:getblock x (1+ y) z)))
	(when (zerop idabove)
	  (sandbox::plain-setblock x y z 2 0))))))

(defun dirts (x y z)
  (let ((blockid (world:getblock x y z)))
    (when (= blockid 1)
      (when (or (zerop (world:getblock x (+ 2 y) z))
		(zerop (world:getblock x (+ 3 y) z)))
	(sandbox::plain-setblock x y z 3 0)))))

(defun find-top (x z min max test)
  (let ((delta (- max min)))
    (dotimes (i delta)
      (let* ((height (- max i 1))
	     (obj (funcall test x height z)))
	(when obj
	  (return-from find-top (values height obj)))))
    (values nil nil)))

(defun enclose ()
  (dobox ((x 0 128)
	  (y 0 128))
	 (sandbox::plain-setblock x y 0   1 0)
	 (sandbox::plain-setblock x y 1   1 0)
	 (sandbox::plain-setblock x y 127 1 0)
	 (sandbox::plain-setblock x y 126 1 0))
  (dobox ((z 0 128)
	  (y 0 128))
	 (sandbox::plain-setblock 0   y z 1 0)
	 (sandbox::plain-setblock 1   y z 1 0)
	 (sandbox::plain-setblock 127 y z 1 0)
	 (sandbox::plain-setblock 126 y z 1 0))
  (dobox ((z 0 128)
	  (x 0 128)
	  (y 0 64))
	 (sandbox::plain-setblock x y z 1 0)))

(defun simple-relight (&optional (box *box*))
  (map-box (lambda (x y z)
	     (let ((blockid (world:getblock x y z)))
					;(unless (zerop blockid))
	       (let ((light (aref mc-blocks:*lightvalue* blockid)))
		 (if (zerop light)
		     (sandbox::plain-setblock x y z blockid 0 0)
		     (sandbox::plain-setblock x y z blockid light)))))
	   box)
  (map-box (lambda (x y z)
	     (multiple-value-bind (height obj)
		 (find-top x z 0 y (lambda (x y z)
				     (not (zerop (world:getblock x y z)))))
	       (declare (ignore obj))
	       (unless height
		 (setf height 0))
	       (dobox ((upup (1+ height) y))
		      (world:skysetlight x upup z 15))))
	   #(0 128 128 129 0 128))
  (map-box (lambda (x y z)
	     (when (= 15 (world:skygetlight x y z))
	       (sandbox::sky-light-node x y z)))
	   *box*)
  (map-box (lambda (x y z)
	     (unless (zerop (world:getblock x y z))
	       (sandbox::light-node x y z)))
	   *box*))

(defun invert (x y z)
  (let ((blockid (world:getblock x y z)))
    (if (= blockid 0)
	(sandbox::plain-setblock x y z 1 ;(aref #(56 21 14 73 15) (random 5))
			0)
	(sandbox::plain-setblock x y z 0 0)
	)))

(defun neighbors (x y z)
  (let ((tot 0))
    (macrolet ((aux (i j k)
		 `(unless (zerop (world:getblock (+ x ,i) (+ y ,j) (+ z ,k)))
		   (incf tot))))
      (aux 1 0 0)
      (aux -1 0 0)
      (aux 0 1 0)
      (aux 0 -1 0)
      (aux 0 0 1)
      (aux 0 0 -1))
    tot))

(defun bonder (x y z)
  (let ((blockid (world:getblock x y z)))
    (unless (zerop blockid)
      (let ((naybs (neighbors x y z)))
	(when (> 3 naybs)		     
	  (sandbox::plain-setblock x y z 0 0 0))))))

(defun bonder2 (x y z)
  (let ((blockid (world:getblock x y z)))
    (when (zerop blockid)
      (let ((naybs (neighbors x y z)))
	(when (< 2 naybs)		     
	  (sandbox::plain-setblock x y z 1 0 0))))))

(defun invert-light (x y z)
  (when (zerop (world:getblock x y z))
    (let ((blockid2 (world:skygetlight x y z)))
      (Setf (world:skygetlight x y z) (- 15 blockid2)))))

(defun edge-bench (x y z)
  (let ((blockid (world:getblock x y z)))
    (unless (zerop blockid)
      (when (= 4 (neighbors x y z))
	(sandbox::plain-setblock x y z 58 0 0)))))

(defun corner-obsidian (x y z)
  (let ((blockid (world:getblock x y z)))
    (unless (zerop blockid)
      (when (= 3 (neighbors x y z))
	(sandbox::plain-setblock x y z 49 0 0)))))


(defun seed (id chance)
  (declare (type (unsigned-byte 8) id))
  (lambda (x y z)
    (let ((blockid (world:getblock x y z)))
      (when (and (zerop blockid)
		 (zerop (random chance)))
	(sandbox::plain-setblock x y z id 0)))))

(defun grow (old new)
  (lambda (x y z)
    (let ((naybs (neighbors2 x y z old)))
      (when (and (not (zerop naybs))
		 (zerop (world:getblock x y z))
		 (zerop (random (- 7 naybs))))
	(sandbox::plain-setblock x y z new 0)))))
(defun sheath (old new)
  (lambda (x y z)
    (when (and (zerop (world:getblock x y z))
	       (not (zerop (neighbors2 x y z old))))
      (sandbox::plain-setblock x y z new 0))))

(defun neighbors2 (x y z w)
  (let ((tot 0))
    (macrolet ((aux (i j k)
		 `(when (= w (world:getblock (+ x ,i) (+ y ,j) (+ z ,k)))
		   (incf tot))))
      (aux 1 0 0)
      (aux -1 0 0)
      (aux 0 1 0)
      (aux 0 -1 0)
      (aux 0 0 1)
      (aux 0 0 -1))
    tot))

(defun testes (&optional (box *box*))
  (map nil
       (lambda (x) (map-box x box))
       (list #'edge-bench
	     #'corner-obsidian
	     (replace-block 49 0)
	     (replace-block 58 0))))

(defun replace-block (other id)
  (declare (type (unsigned-byte 8) id))
  (lambda (x y z)
    (let ((blockid (world:getblock x y z)))
      (when (= other blockid)
	(world:setblock x y z id)))))

(defun dirt-sand (x y z)
  (let ((blockid (world:getblock x y z)))
    (case blockid
      (2 (sandbox::plain-setblock x y z 12 0))
      (3 (sandbox::plain-setblock x y z 24 0)))))

(defun cactus (x y z)
  (let ((trunk-height (+ 1 (random 3))))
    (dobox ((y0 0 trunk-height))
	   (sandbox::plain-setblock (+ x 0) (+ y y0) (+ z 0) 81 0 0))))

(defun growdown (old new)
  (lambda (x y z)
    (flet ((neighbors3 (x y z w)
	     (let ((tot 0))
	       (macrolet ((aux (i j k)
			    `(when (= w (world:getblock (+ x ,i) (+ y ,j) (+ z ,k)))
			       (incf tot))))
		 (aux 1 0 0)
		 (aux -1 0 0)
		 (aux 0 1 0)
		 (aux 0 0 1)
		 (aux 0 0 -1))
	       tot)))
      (let ((naybs (neighbors3 x y z old)))
	(when (and (not (zerop naybs))
		   (zerop (world:getblock x y z))
		   (zerop (random (- 7 naybs))))
	  (sandbox::plain-setblock x y z new 0))))))

#+nil
#(1 2 3 4 5 7 12 13 ;14
  15 16 17 18 19 21 22 23 24 25 35 41 42 43 45 46 47 48 49
   54 56 57 58 61 61 73 73 78 82 84 86 87 88 89 91 95)

#+nil
'("lockedchest" "litpumpkin" "lightgem" "hellsand" "hellrock" "pumpkin"
 "jukebox" "clay" "snow" "oreRedstone" "oreRedstone" "furnace" "furnace"
 "workbench" "blockDiamond" "oreDiamond" "chest" "obsidian" "stoneMoss"
 "bookshelf" "tnt" "brick" "stoneSlab" "blockIron" "blockGold" "cloth"
 "musicBlock" "sandStone" "dispenser" "blockLapis" "oreLapis" "sponge" "leaves"
 "log" "oreCoal" "oreIron" "oreGold" "gravel" "sand" "bedrock" "wood"
 "stonebrick" "dirt" "grass" "stone")

#+nil
(defun define-time ()
  (eval
   (defun fine-time ()
      (/ (%glfw::get-timer-value)
	 ,(/ (%glfw::get-timer-frequency) (float (expt 10 6)))))))

#+nil
(defun seeder ()
  (map nil
       (lambda (ent)
	 (let ((pos (sandbox::farticle-position (sandbox::entity-particle ent))))
	   (setf (sandbox::entity-fly? ent) nil
		 (sandbox::entity-gravity? ent) t)
	   (setf (aref pos 0) 64.0
		 (aref pos 1) 128.0
		 (aref pos 2) -64.0))) *ents*))

#+nil
(map nil (lambda (ent)
	   (unless (eq ent *ent*)
	     (setf (sandbox::entity-jump? ent) t)
	     (if (sandbox::entity-hips ent)
		 (incf (sandbox::entity-hips ent)
		       (- (random 1.0) 0.5))
		 (setf (sandbox::entity-hips ent) 1.0))
	     )
	   (sandbox::physentity ent)) *ents*)


#+nil
(progno
 (dotimes (x (length fuck::*ents*))
   (let ((aaah (aref fuck::*ents* x)))
     (unless (eq aaah fuck::*ent*)
       (gl:uniform-matrix-4fv
	pmv
	(cg-matrix:matrix* (camera-matrix-projection-view-player camera)
			   (compute-entity-aabb-matrix aaah partial))
	nil)
       (gl:call-list (getfnc :box))))))

(defun yoy ()
  (world:clearworld)
  (map-box (seed 3 800))
  (dotimes (x 5)
    (map-box (sheath 3 4))
    (map-box (sheath 4 3)))
  (map-box #'bonder))

(defun upsheath (old new)
  (lambda (x y z)
    (flet ((neighbs (x y z w)
	     (let ((tot 0))
	       (macrolet ((aux (i j k)
			    `(when (= w (world:getblock (+ x ,i) (+ y ,j) (+ z ,k)))
			       (incf tot))))
		 (aux 1 0 0)
		 (aux -1 0 0)
		 (aux 0 -1 0)
		 (aux 0 0 1)
		 (aux 0 0 -1))
	       tot)))
      (let ((naybs (neighbs x y z old)))
	(when (and (not (zerop naybs))
		   (zerop (world:getblock x y z)))
	  (sandbox::plain-setblock x y z new 0))))))


(defun wowz (&optional (times 1000))
  (let ((x 64)
	(oldx 0)
	(y 64)
	(oldy 0)
	(z 64)
	(oldz 0)
	(xvel 0)
	(yvel 0)
	(zvel 0))  
    (flet ((rand ()
	     (let ((a 2))
	       (- (random (+ 1 a)) (/ a 2))))
	   (out-of-bounds (x)
	     (or (<= 128 x)
		 (< x 0))))
      (dotimes (index times)
	(setf oldx x
	      oldy y
	      oldz z)
	(setf xvel (* xvel 0.9)
	      yvel (* yvel 0.9)
	      zvel (* zvel 0.9))
	(incf xvel (rand))
	(incf yvel (rand))
	(incf zvel (rand))
	(let ((a (max (abs xvel) (abs zvel))))
	  (setf yvel (alexandria:clamp yvel
				       (- a)
				       a)))
	(let ((x (+ x xvel))
	      (y (+ y yvel))
	      (z (+ z zvel)))
	  (when (out-of-bounds x)
	    (setf xvel (- xvel)))
	  (when (out-of-bounds y)
	    (setf yvel (- yvel)))
	  (when (out-of-bounds z)
	    (setf zvel (- zvel))))
	(incf x xvel)
	(incf y yvel)
	(incf z zvel)
	(line x y z
	      oldx oldy oldz)))))

(defun line (px py pz vx vy vz)
  (sandbox::aabb-collect-blocks
   px py pz (- vx px) (- vy py) (- vz pz)
   sandbox::*fist-aabb*   
   (lambda (x y z)
     (sandbox::plain-setblock x y z 1 0))))

(defun pumpkinify (x y z)
  (when (and (= 2 (world::getblock x y z))
	     (zerop (random 256))
	     (not (= 6 (neighbors x y z))))
    (sandbox::plain-setblock x y z 89 15)))

(defun map-all-chunks (fun)
  (maphash (lambda (k v)
	     (declare (ignore v))
	     (multiple-value-bind (x y z) (world:unhashfunc k)
	       (dobox ((a x (+ x 16))
		       (b y (+ y 16))
		       (c z (+ z 16)))
		      (funcall fun a c b))))
	   world::chunkhash))

(defun map-all-chunks1 (fun)
  (maphash (lambda (k v)
	     (declare (ignore v))
	     (multiple-value-bind (x y z) (world:unhashfunc k)
	       (funcall fun x y z)))
	   world::chunkhash))

(defun tree (x y z)
  (let ((trunk-height (+ 1 (random 3))))
    (let ((yup (+ y trunk-height)))
      (dobox ((z0 -2 3)
	      (x0 -2 3)
	      (y0 0 2))
	     (unless (and (or (= z0 -2)
			      (= z0 2))
			  (or (= x0 -2)
			      (= x0 2))
			  (zerop (random 2)))
	       (sandbox::plain-setblock (+ x x0) (+ yup y0) (+ z z0) 18 0 0))))
    (let ((yup (+ y trunk-height 2)))
      (dobox ((x0 -1 2)
	      (z0 -1 2)
	      (y0 0 2))
	     (unless (and
		      (= y0 1)
		      (or (= z0 -1)
			  (= z0 1))
		      (or (= x0 -1)
			  (= x0 1))
		      (zerop (random 2)))
	       (sandbox::plain-setblock (+ x x0) (+ yup y0) (+ z z0) 18 0 0))))
    (dobox ((y0 y (+ y (+ 3 trunk-height))))
	   (sandbox::plain-setblock x y0 z 17 0 0))))

#+nil
(progno
 (in-package :sandbox)

 (defun setatest (x)
   (prog2 (setf atest
		(case x
		  (0 (byte-read #P "/home/terminal256/.minecraft/saves/New World-/region/r.0.-1.mcr"))
		  (1 (byte-read #P "/home/imac/.minecraft/saves/New World/region/r.1.1.mcr"))
		  (2 (cl-mc-shit::testchunk))
		  (3 (byte-read #P "/home/imac/info/mcp/jars/saves/New World/region/r.-1.-1.mcr"))
		  ))
       x))

 (defparameter atest nil)
 ;;(setatest 3)

 (defun someseq (x y)
   (let* ((thechunk (helpchunk (+ 24 x) y)))
     (if thechunk
	 (let ((light (getlightlizz thechunk))
	       (blocks (getblockslizz thechunk))
	       (skylight (getskylightlizz thechunk))
	       (meta (getmetadatalizz thechunk))
					;      (leheight (getheightlizz thechunk))
	       )
	   (let ((xscaled (ash x 4))
		 (yscaled (ash y 4)))
	     (progn (sandbox::flat3-chunk
		     light
		     (lambda (x y z b)
		       (setf (world:getlight x y z) b))
		     xscaled 0 yscaled)
		    (sandbox::flat3-chunk
		     skylight
		     (lambda (x y z b)
		       (setf (world:skygetlight x y z) b))
		     xscaled 0 yscaled)
		    (sandbox::flat3-chunk
		     meta
		     (lambda (x y z b)
		       (setf (world:getmeta x y z) b))
		     xscaled 0 yscaled)
		    (progno (sandbox::flat2-chunk
			     leheight
			     (lambda (x y b)
			       (setf (world::getheight x y) b))
			     xscaled yscaled)))
	     (sandbox::flat3-chunk
	      blocks
	      (lambda (x y z b)
		(unless (zerop b)
		  (setf  (world:getblock x y z) b)))
	      xscaled 0 yscaled))))))

 (defun flat3-chunk (data setfunc xoffset yoffset zoffset)
   (dotimes (wow 8)
     (dotimes (j 16)
       (dotimes (i 16)
	 (dotimes (k 16)
	   (funcall setfunc (+ xoffset i) (+ yoffset (* 16 wow) j) (+ zoffset k)
		    (elt data (+ (* i 16 128) (+ j (* 16 wow)) (* k 128)))))))))

 (defun flat2-chunk (data setfunc xoffset yoffset)
   (dotimes (j 16)
     (dotimes (i 16)
       (funcall setfunc (+ xoffset i) (+ yoffset j)
		(elt data (+ i (+ (* 16 j))))))))

 (defun helpchunk (x y)
   (let ((thechunk  (cl-mc-shit:mcr-chunk atest x y)))
     (if thechunk
	 (cl-mc-shit:chunk-data
	  thechunk)
	 nil)))

 (defun expand-nibbles (vec)
   (let* ((len (length vec))
	  (newvec (make-array (* 2 len) :element-type '(unsigned-byte 8))))
     (dotimes (x len)
       (multiple-value-bind (a b) (floor (aref vec x) 16)
	 (setf (aref newvec (* 2 x)) b)
	 (setf (aref newvec (1+ (* 2 x))) a)))
     newvec))

 (defun nbt-open (lizz)
   (third
    (first
     (third
      lizz))))

 (defun gettag (lestring lizz)
   (dolist (tag lizz)
     (if (equal lestring (second tag))
	 (return-from gettag (third tag)))))

 (defun getmetadatalizz (lizz)
   (expand-nibbles
    (gettag "Data"
	    (nbt-open lizz))))

 (defun getskylightlizz (lizz)
   (expand-nibbles
    (gettag "SkyLight"
	    (nbt-open lizz))))


 (defun getlightlizz (lizz)
   (expand-nibbles
    (gettag "BlockLight"
	    (nbt-open lizz))) )
 (defun getblockslizz (lizz)
   (gettag
    "Blocks"
    (nbt-open lizz)))

 (defun getheightlizz (lizz)
   (gettag
    "HeightMap"
    (nbt-open lizz)))
 )
