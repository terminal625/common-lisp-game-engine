(defpackage #:sandbox-sub
  (:use :cl :utility :application :struct-to-clos))
(in-package #:sandbox-sub)
(define-modify-macro logiorf (&rest args) logior)

(defun collide-world2 (aabb-gen-fnc x y z dx dy dz aabb)
  (multiple-value-bind (new-x new-y new-z xyzclamp)
      (step-motion aabb-gen-fnc
		   x y z dx dy dz aabb)
    (values new-x new-y new-z
	    (if (logtest #b100 xyzclamp) 0 dx)
	    (if (logtest #b010 xyzclamp) 0 dy)
	    (if (logtest #b001 xyzclamp) 0 dz))))
(define-modify-macro *= (&rest args) *)
(defun step-motion (get-collision-data px py pz vx vy vz aabb)
  (let ((dead-axis #b000) ;;axis which are zeroed
	(clamp #b000)) ;;the final clamping value for each axis
    (flet ((deadify (x bit)
	     (when (zerop x)
	       (logiorf dead-axis bit))))
      (deadify vx #b100)
      (deadify vy #b010)
      (deadify vz #b001))
    (loop
       (flet ((exit ()
		(return (values px py pz clamp))))
	 (if (= #b111 dead-axis) ;;all velocities are zero
	     (exit)
	     (multiple-value-bind (newclamp ratio)
		 (funcall get-collision-data px py pz vx vy vz aabb)
	       (logiorf clamp newclamp)
	       (let ((whats-left (- 1 ratio)))
		 (macrolet ((axis (pos vel bit)
			      `(unless (logtest ,bit dead-axis)
				 (incf ,pos (* ratio ,vel))
				 (if (logtest ,bit newclamp)
				     (setf ,vel 0)
				     (*= ,vel whats-left)))))
		   (axis px vx #b100)
		   (axis py vy #b010)
		   (axis pz vz #b001))
		 (when (>= 0 whats-left) (exit)))
	       (logiorf dead-axis newclamp)))))))

;;;;
(defparameter *dirtying2* nil)
(defun collide-fucks (px py pz vx vy vz aabb)
  (aabbcc::with-touch-collector (collect-touch collapse-touch min-ratio)
    (aabbcc::aabb-collect-blocks (px py pz vx vy vz aabb)
	(x y z contact)
      (declare (ignorable contact))
      (when (aref mc-blocks:*iscollidable*
		  (world:getblock x y z))
	(when *dirtying2*
	  (sandbox::plain-setblock x y z (1+ (random 5)) 0))
	(multiple-value-bind (minimum type)
	    (aabbcc:aabb-collide
	     aabb
	     px py pz
	     *block-aabb*
	     x y z
	     vx vy vz)
	  (collect-touch minimum type))))
    (values
     (collapse-touch vx vy vz)
     min-ratio)))

(defparameter *dirtying* nil)
(defun a-contact-fun (px py pz aabb)
  (let ((acc #b000000))
    (aabbcc::get-blocks-around (px py pz aabb) (mx my mz contact-var)
      (declare (ignorable contact-var))
      (when (aref mc-blocks:*iscollidable* (world:getblock mx my mz))
	(when *dirtying*
	  (sandbox::plain-setblock mx my mz (1+ (random 5)) 0))
	(logiorf acc (aabbcc:aabb-contact px py pz aabb mx my mz *block-aabb*))))
    acc))

;;;
(define-modify-macro *= (&rest args)
  *)
(defun physics (yaw dir farticle
		noclip gravity fly
		is-jumping
		is-sneaking
		contact-handler
		world-collision-fun
		aabb)
  (let ((tickscale (/ 1.0 3.0)))
    (step-farticle farticle)
    (let ((vel (farticle-velocity farticle))
	  (pos (farticle-position farticle)))
      (let ((contact-state (if (and noclip (not sandbox-sub::*dirtying*))
			       #b000000
			       (with-vec (px py pz) (pos)
				 (funcall contact-handler px py pz aabb)))))
	(let ((onground (logtest contact-state #b000100)))
	  (let ((speed (* 0.4 (expt tickscale 2))))
	    (with-vec (xvel yvel zvel) (vel symbol-macrolet)
	      (if fly
		  (progn
		    (when is-jumping
		      (incf yvel speed))
		    (when is-sneaking
		      (decf yvel speed)))
		  
		  (if onground
		      (when is-jumping
			(incf yvel (* 0.49 (expt tickscale 1))))
		      (setf speed (* speed 0.2))))
	      (when dir
		(let ((dir (+ dir yaw)))
		  (incf xvel (* speed (sin dir)))
		  (incf zvel (* speed (cos dir)))))))
	  (contact-handle contact-state vel)
	  (let ((fun (if noclip
			 (lambda (&rest args)
			   (declare (ignore args))
			   (values #b000 1.0))
			 (progn
			   world-collision-fun))))
	    (with-vec (vx vy vz) (vel symbol-macrolet)
	      (with-vec (px py pz) (pos symbol-macrolet)
		(setf (values px py pz vx vy vz)
		      (collide-world2
		       fun
		       px py pz vx vy vz aabb)))))
	  (let ((air-friction 0.98)
		(walking-friction (* 0.6 0.9)))
	    (with-vec (xvel yvel zvel) (vel symbol-macrolet)
	      (if fly
		  (progn
		    (setf air-friction 0.9)
		    (*= xvel air-friction)
		    (*= zvel air-friction))
		  (progn
		    (setf air-friction 0.98)
		    (cond (onground
			   (*= xvel walking-friction)
			   (*= zvel walking-friction))
			  (t (*= xvel 0.9)
			     (*= zvel 0.9)
			     ))))
	      (when (and (not onground)
			 gravity)
		(decf yvel (* 0.08 (expt tickscale 2))))
	      (*= yvel air-friction))))))))

(defun contact-handle (acc vel)
  (multiple-value-bind (i+ i- j+ j- k+ k-)
      (values (logtest acc #b100000)
	      (logtest acc #b010000)
	      (logtest acc #b001000)
	      (logtest acc #b000100)
	      (logtest acc #b000010)
	      (logtest acc #b000001))
    (with-vec (xvel yvel zvel) (vel symbol-macrolet)
      (etouq 
       (cons
	'progn
	(mapcar
	 (lambda (args)
	   (apply
	    (lambda (axis plus minus)
	      (alexandria:with-gensyms (var)
		`(let ((,var ,axis))
		   (when (or (and (plusp ,var) ,plus)
			     (and (minusp ,var) ,minus))
		     (setf ,axis 0.0)))))
	    args))
	 '((xvel i+ i-)
	   (yvel j+ j-)
	   (zvel k+ k-))))))))

(defparameter *block-aabb*
  (aabbcc:make-aabb
   :minx 0.0
   :miny 0.0
   :minz 0.0
   :maxx 1.0
   :maxy 1.0
   :maxz 1.0))

(defparameter *player-aabb*
 ; #+nil
  (aabbcc:make-aabb
   :minx -0.3
   :miny -1.5
   :minz -0.3
   :maxx 0.3
   :maxy 0.12
   :maxz 0.3)
  #+nil
  (aabbcc:make-aabb
   :minx -5.0
   :miny -5.0
   :minz -5.0
   :maxx 5.0
   :maxy 5.0
   :maxz 5.0))

(struct->class
 (defstruct entity
   particle ;;center of mass
   neck ;;
   hips ;; walking direction
   aabb 
   contact ;;touching each side
   fly?
   gravity?
   clip?
   jump?
   sneak?
   collision-fun
   contact-fun))

(defun gentity ()
  (make-entity :collision-fun (function collide-fucks)
	       :contact-fun (function a-contact-fun)
	       :particle (make-farticle)
	       :neck (make-necking)
	       :aabb *player-aabb*
	       :hips nil
	       :contact #b000000
	       :fly? t
	       :gravity? nil
	       :clip? t
	       :jump? nil
	       :sneak? nil))

(defun physentity (entity)
  (physics
   (necking-yaw (entity-neck entity))
   (entity-hips entity)
   (entity-particle entity)
   (not (entity-clip? entity))
   (entity-gravity? entity)
   (entity-fly? entity)
   (entity-jump? entity)
   (entity-sneak? entity)
   (entity-contact-fun entity)
   (entity-collision-fun entity)
   (entity-aabb entity)))

(defparameter *fist-aabb*
     ;;;a very small cubic fist
  (aabbcc:make-aabb
   :minx -0.005
   :miny -0.005
   :minz -0.005
   :maxx 0.005
   :maxy 0.005
   :maxz 0.005))

;;;;;;;
(struct->class
 (defstruct fister
   (selected-block (vector 0 0 0))
   (normal-block (vector 0 0 0))
   (exists nil)
   (position (vector 0 0 0))
   fun))

(defun standard-fist (fist px py pz vx vy vz)
  (multiple-value-bind (xyzclamp frac) (funcall (fister-fun fist) px py pz vx vy vz *fist-aabb*)
    (if (= #b000 xyzclamp)
	(setf (fister-exists fist) nil)
	(progn
	  (macrolet ((setvec3d (vec x y z)
	     (let ((a (gensym)))
	       `(let ((,a ,vec))
		  (setf (aref ,a 0) ,x
			(aref ,a 1) ,y
			(aref ,a 2) ,z)))))
	    (let ((a (+ px (* frac vx)))
		  (b (+ py (* frac vy)))
		  (c (+ pz (* frac vz))))
	      (let ((dx (if (logtest xyzclamp #b100)
			    (if (plusp vx) 1 -1) 0))
		    (dy (if (logtest xyzclamp #b010)
			    (if (plusp vy) 1 -1) 0))
		    (dz (if (logtest xyzclamp #b001)
			    (if (plusp vz) 1 -1) 0)))
		(setvec3d (fister-selected-block fist)
			  (floor (+ dx a))
			  (floor (+ dy b))
			  (floor (+ dz c))))
	      (setvec3d (fister-position fist)
			a 
			b
			c)
	      (setvec3d (fister-normal-block fist)
			(floor a) 
			(floor b)
			(floor c))))
	  (setf (fister-exists fist) t)))))

(defun gen-fister ()
  (let ((fist (make-fister)))
    (setf (fister-fun fist) #'collide-fucks)
    fist))
;;;;;;;;;;;;;;;;;;;;

;;;;150 ms delay for sprinting
;;;;player eye height is 1.5, subtract 1/8 for sneaking

;;gravity is (* -0.08 (expt tickscale 2)) 0 0
;;falling friction is 0.98
;;0.6 * 0.91 is walking friction

;;fov::
;;70 is normal
;;110 is quake pro


;;;;;
(defun unit-pitch-yaw (result pitch yaw)
  (let ((cos-pitch (cos pitch)))
    (setf (aref result 0) (* cos-pitch (sin yaw))
	  (aref result 1) (sin pitch)
	  (aref result 2) (* cos-pitch (cos yaw))))
  result)

(struct->class
 (defstruct necking
   (yaw 0.0)
   (pitch 0.0)))

(defun lookaround2 (neck newyaw newpitch)
  (setf (necking-yaw neck) newyaw
	(necking-pitch neck) newpitch))
(defun necktovec (neck result-vec)
  (unit-pitch-yaw result-vec
		  (necking-pitch neck)
		  (necking-yaw neck)))
;;;;;;;

(struct->class
 (defstruct farticle
   (position (nsb-cga:vec 0.0 0.0 0.0))
   (position-old (nsb-cga:vec 0.0 0.0 0.0))
   (velocity (vector 0.0 0.0 0.0))))

(defun step-farticle (p)
  (let ((old (farticle-position-old p))
	(curr (farticle-position p)))
    (nsb-cga:%copy-vec old curr)))
(defun farticle-to-camera (farticle camera fraction)
  (let ((curr (farticle-position farticle))
	(prev (farticle-position-old farticle)))
    (let ((vec (camera-matrix:camera-vec-position camera))
	  (cev (camera-matrix:camera-vec-noitisop camera)))
      (nsb-cga:%vec-lerp vec prev curr fraction)
      (nsb-cga:%vec* cev vec -1.0))))
(defun entity-to-camera (entity camera fraction)
  (necktovec (entity-neck entity)
		      (camera-matrix:camera-vec-forward camera))	  
  (farticle-to-camera (entity-particle entity)
		      camera
		      fraction))

(defun change-entity-neck (entity yaw pitch)
  (let ((neck (entity-neck entity)))
    (lookaround2 neck yaw pitch)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(deflazy gl-init (gl-context)
  (declare (ignorable application::gl-context))
  (clrhash sandbox::*g/chunk-call-list*))

(defun per-frame (session)
  (declare (ignorable session))
  (getfnc 'gl-init)
  (render-stuff))

(defparameter *fov*
  ((lambda (deg)
     (* deg (coerce (/ pi 180.0) 'single-float)))
   (nth 1 '(95 70))))

(defparameter *black* (make-instance 'application::render-area :height 2 :width 2
				     :x 0
				     :y 0))
(defparameter *render-ticks* 0)
(defun render-stuff ()
  ((lambda (width height)
     (let ((camera *camera*))
       (setf (camera-matrix:camera-aspect-ratio camera)
	     (/ (coerce width 'single-float)
		(coerce height 'single-float))))
     (let ((render-area *render-area*))
       (setf (render-area-width render-area) (* width (/ 1.0 1.0)) 
	     (render-area-height render-area) (* height (/ 1.0 1.0))
	     (render-area-x render-area) 0
	     (render-area-y render-area) 0
	     )))
   window::*width* window::*height*)
  (glhelp::bind-default-framebuffer)
  (set-render-area *render-area*)
  (set-sky-color)
  (setf (camera-matrix:camera-fov *camera*) *fov*)
  (setf (camera-matrix:camera-frustum-far *camera*) (* 1024.0 256.0))
  (camera-matrix:update-matrices *camera*)
  ;;;render chunks
  (camera-shader *camera*)
  ;;;render crosshairs
;  #+nil
  (progn
    ((lambda (width height)
       (let ((render-area *black*))
	 (setf
	  (render-area-x render-area) (- (* width (/ 1.0 2.0)) 1.0) 
	  (render-area-y render-area) (- (* height (/ 1.0 2.0)) 1.0)
	  )))
     window::*width* window::*height*)
    (set-render-area *black*)
    (gl:clear-color 1.0 1.0 1.0 1.0)
    (gl:clear
     :color-buffer-bit
     ))
  (incf *render-ticks*))

(defun set-sky-color ()
  (let ((daytime sandbox::*daytime*))
    (let ((r (* daytime (aref *sky-color* 0)))
	  (g (* daytime (aref *sky-color* 1)))
	  (b (* daytime (aref *sky-color* 2))))
      (gl:clear-color r g b 1.0))))
(defparameter *sky-color*
  #+nil
  (vector 0.68 0.8 1.0)
  #+nil
  (map 'vector (lambda (x) (/ x 255.0)) (vector 97 138 255))
  ;#+nil
  (vector 0.0 0.0 0.0))
  
(defparameter *fog-ratio* 0.75)

(defun camera-shader (camera)
  (declare (optimize (safety 3) (debug 3)))
  (glhelp::use-gl-program (getfnc 'blockshader))

  (let ((matrix
	 (camera-matrix:camera-matrix-projection-view-player camera)))
    (gl:clear-depth 1.0)
    (gl:clear
     :color-buffer-bit
     :depth-buffer-bit)
    (gl:depth-func :less)

    (glhelp:with-uniforms uniform (getfnc 'blockshader)
      (gl:uniform-matrix-4fv 
       (uniform :pmv)
       matrix
       nil)
      (flet ((fractionalize (x)
	       (alexandria:clamp x 0.0 1.0)))
	(let ((time sandbox::*daytime*))
	  (let ((x (fractionalize (* (aref *sky-color* 0) time)))
		(y (fractionalize (* (aref *sky-color* 1) time)))
		(z (fractionalize (* (aref *sky-color* 2) time))))
	    (%gl:uniform-3f (uniform :fogcolor)
			    x y z)
	    (gl:uniformfv (uniform :camera-pos)
			  (camera-matrix:camera-vec-position *camera*))
	    (%gl:uniform-1f (uniform :foglet)
			    (/ -1.0 (or 128 (camera-matrix:camera-frustum-far *camera*)) *fog-ratio*))
	    (%gl:uniform-1f (uniform :aratio)
			    (/ 1.0 *fog-ratio*)))))

      (progn
	(gl:uniformi (uniform :sampler) 0)
	(glhelp::set-active-texture 0)
	(gl:bind-texture :texture-2d
			 (glhelp::handle (getfnc 'terrain))
			 ))
      #+nil
      (gl:uniformf 
       (uniform :time)
       (float (/ (get-internal-real-time)
		 100.0)))))
  (gl:enable :depth-test)
  
  (gl:enable :cull-face)
  (gl:disable :blend)
  (sandbox::draw-world)
  (sandbox::designatemeshing))

;;seizures are so FUN!
#+nil
#(:clear :set :copy :copy-inverted
  :noop :invert :and :nand :or :nor
  :xor :equiv :and-reverse :and-inverted :or-reverse :or-inverted)
(progn
  (defun color-grasses (terrain color)
    (modify-greens 64 192 :color color :terrain terrain)
    (modify-greens 80 192 :color color :terrain terrain)
    (modify-greens 0 240 :color color :terrain terrain)
    terrain)
  (defun getapixel (h w image)
    (destructuring-bind (height width c) (array-dimensions image)
      (declare (ignore height))
      (make-array 4 :element-type (array-element-type image)
		  :displaced-to image
		  :displaced-index-offset (* c (+ w (* h width))))))

  #+nil
  (#(1742848/8775 2673664/8775 1079296/8775 255)
    (getapixel 0 0 grass-tint)
    (getapixel 255 255 grass-tint))
;;minecraft fog color sometimes (0.68 0.8 1.0)
  ;;  (progno #(113 174 70 255)  #(198 304 122 255))
;;;grass is 0 240
;;;leaves is [64 80] 192
  (defun modify-greens (xpos ypos
			&key
			  (color #(0 0 0 0))
			  (terrain (error "no image")))
    (dobox ((x xpos (+ 16 xpos)) (y ypos (+ 16 ypos)))
	   ((lambda (vecinto other)
	      (map-into vecinto (lambda (a b) (truncate (* a b) 256)) vecinto other))
	    (getapixel (- 255 y) x terrain) color))))

;;;;load a png image from a path

(defun load-png (filename)
  (opticl:read-png-file filename))

(defvar *ourdir* (filesystem-util:this-directory))

(deflazy terrain-png ()
  (load-png 
   (filesystem-util:rebase-path #P"terrain.png" *ourdir*)))

(deflazy modified-terrain-png (terrain-png grass-png)
  (color-grasses
   (alexandria::copy-array terrain-png)
   (let ((value (random 256)))
     (getapixel value (random (1+ value)) grass-png))))

(deflazy terrain (modified-terrain-png gl-context)
  (make-instance
   'glhelp::gl-texture
   :handle
   (prog1
       (glhelp:pic-texture
	modified-terrain-png
	:rgba)
     (glhelp:apply-tex-params
      (quote ((:texture-min-filter . :nearest)
	      (:texture-mag-filter . :nearest)
	      (:texture-wrap-s . :repeat)
	      (:texture-wrap-t . :repeat)))))))
(deflazy grass-png ()
  (load-png 
   (filesystem-util:rebase-path #P"grasscolor.png" *ourdir*)))
(deflazy blockshader (blockshader-text gl-context)
  (glhelp::create-gl-program blockshader-text))

(deflazy blockshader-text ()
  (glslgen::ashader
   :version 120
   :vs
   (glslgen2::make-shader-stage
    :out '((color-out "float")
	   (texcoord-out "vec2")
	   
	   (fogratio-out "float"))
    :in '((position "vec4")
	  (texcoord "vec2")
	  (color "float")
	  (projection-model-view "mat4")

	  (foglet "float")
	  (aratio "float")
	  (camera-pos "vec3"))
    :program
    '(defun "main" void ()
      (= "gl_Position" (* projection-model-view position))
      (= color-out color)
      (= texcoord-out texcoord)

      (= fogratio-out (min 1.0 (+ (* foglet (distance camera-pos (|.| position "xyz"))) aratio)))))
   :frag
   (glslgen2::make-shader-stage
    :in '((texcoord "vec2")
	  (color "float")
	  (sampler "sampler2D")

	  (fogratio "float")
	  (fogcolor "vec3")
;;						     (wombo ("float" 4) "{2.0, 10.4, 1.0, 10.0}")
	  )
    :program
    '(defun "main" void ()
      (/**/ vec4 pixdata)
      (= pixdata ("texture2D" sampler texcoord))
      #+nil
      (if (> (|.| pixdata "g") 0.5)
	  (progn
	    "discard"))
      ;;      (= (|.| pixdata "rgb") (|.| pixdata "ggr"))
      (/**/ vec3 temp)
      (= temp 
       (mix 
	fogcolor
	(* color
	   (|.| pixdata "rgb"))
	fogratio
	))
      ;;      	 (*= temp ([] wombo (int (* 4.0 (|.| temp "g")))))
      (= (|.| :gl-frag-color "rgb") temp)))
   :attributes
   '((position . 2) 
     (texcoord . 8)
     (color . 0))
   :varyings
   '((color-out . color)
     (texcoord-out . texcoord)
     (fogratio-out . fogratio))
   :uniforms
   '((:pmv (:vertex-shader projection-model-view))
     (:fogcolor (:fragment-shader fogcolor))
     (:foglet (:vertex-shader foglet))
     (:aratio (:vertex-shader aratio))
     (:camera-pos (:vertex-shader camera-pos))
     (:sampler (:fragment-shader sampler)))))