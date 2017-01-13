(in-package :sandbox)

;;;;150 ms delay for sprinting
;;;;player eye height is 1.5, subtract 1/8 for sneaking

;;gravity is (* -0.08 (expt tickscale 2)) 0 0
;;falling friction is 0.98
;;0.6 * 0.91 is walking friction

;;fov::
;;70 is normal
;;110 is quake pro


(defparameter *yaw* nil)
(defparameter *pitch* nil)
(defparameter *xpos* nil)
(defparameter *ypos* nil)
(defparameter *zpos* nil)
(defparameter defaultfov 70)

(defparameter *xvel* 0)
(defparameter *yvel* 0)
(defparameter *zvel* 0)

(defparameter air-friction 0.2)
(defparameter air-friction 0.98)
(defparameter walking-friction (* 0.6 0.9))

(defparameter noclip t)
(defparameter gravity t)
(defparameter fly t)

(defparameter onground nil)

(setf *xpos* 0
      *ypos* 0
      *zpos* 0
      *yaw* 0
      *pitch* 0)

(defun controls ()
  (let ((speed (* 0.4 (expt tickscale 2))))
    (when fly
      (setf speed 0.024)
      (when (e:key-p :space)
	(incf *yvel* speed))
      (when (e:key-p :left-shift)
	(decf *yvel* speed)))
    (unless fly
      (when onground
	(when (e:key-p :space)
	  (incf *yvel* (* (if t 0.49 0.42) (expt tickscale 1)))))
      (unless onground
	(setf speed (* speed 0.2))))    
    (let ((dir (complex 0 0)))
      (when (e:key-p :w)
	(incf dir #C(-1 0)))
      (when (e:key-p :a)
	(incf dir #C(0 1)))
      (when (e:key-p :s)
	(incf dir #C(1 0)))
      (when (e:key-p :d)
	(incf dir #C(0 -1)))
      (unless (zerop dir)
	(let ((rot-dir (* dir (cis *yaw*))))
	  (let ((normalized (/ rot-dir (complex-modulus rot-dir))))
	    (incf *xvel* (* speed (realpart normalized)))
	    (incf *zvel* (* speed (imagpart normalized)))))))))

(defparameter mouse-sensitivity (* 60.0 pi 1/180))

(defun mouse-looking ()
  (multiple-value-bind (dx dy) (delta)
    (let ((x (* mouse-sensitivity (/ dx 360.0)))
	  (y (* mouse-sensitivity (/ dy 360.0))))
      (multiple-value-bind (dyaw dpitch) (%sphere-mouse-help x y)
	(setf *yaw* (mod (+ *yaw* dyaw) (* 2 pi)))
	(setf *pitch* (clamp (+ *pitch* dpitch)
			     (* 0.99 (/ pi -2))
			     (* 0.99 (/ pi 2))))))))

(defparameter old-mouse-x 0)
(defparameter old-mouse-y 0)
(defun delta ()
  (multiple-value-bind (newx newy) (window:get-mouse-position)
    (multiple-value-prog1 (values
			   (- newx old-mouse-x)
			   (- newy old-mouse-y))
      (setf old-mouse-x newx
	    old-mouse-y newy))))


(defun %sphere-mouse-help (x y)
  (if (zerop x)
      (if (zerop y)
	  (values 0.0 0.0)
	  (values 0.0 y))
      (if (zerop y)
	  (values x 0.0)
	  (new-direction (coerce x 'single-float)
			 (coerce y 'single-float)))))


(defparameter mousecapturestate nil)
(defun remove-spurious-mouse-input ()
  (if (window:mice-locked-p)
      (case mousecapturestate
	((nil) 
	 (delta) ;;toss spurious mouse movement 
	 (setf mousecapturestate :justcaptured))
	(:justcaptured (setq mousecapturestate t))
	((t)))
      (setq mousecapturestate nil)))

(defun set-render-cam-pos (millisecs)
  (let ((multiplier (/ millisecs tick-delay)))
    (setf (camera-xpos *camera*) (+ *xpos* (* multiplier *xvel*))
	  (camera-ypos *camera*) (+ *ypos* (* multiplier *yvel*))
	  (camera-zpos *camera*) (+ *zpos* (* multiplier *zvel*))
	  (camera-pitch *camera*) *pitch*
	  (camera-yaw *camera*) *yaw*)))

(defun set-render-cam-look ()
  (setf (camera-pitch *camera*) *pitch*
	(camera-yaw *camera*) *yaw*))

(defparameter daytime 1.0)
(defparameter ticks/sec nil)
(defparameter tickscale nil)

(defun physinnit ()
  (setf ticks/sec 60.0)
  (setf tickscale (/ 20.0 ticks/sec))
  (setf tick-delay (/ 1000000.0 ticks/sec)))

(defun physics ()
  ;;escape to quitx
  (when (e:key-p :ESCAPE) (setq alivep nil))  
  ;;e to escape mouse
  (when (e:key-j-p :E) (window:toggle-mouse-capture))

  (when (window:mice-locked-p)
    (when (e:key-j-p :v) (toggle noclip))
    (when (e:key-j-p :g) (toggle gravity))
    (when (e:key-j-p :f) (toggle fly))
    (if fly
	(setf air-friction 0.9)
	(setf air-friction 0.98))
    (controls)
    (when (e:mice-j-p :right)
      (setblock-with-update (floor fistx)
			    (floor fisty)
			    (floor fistz)
			    49
			    0))
    (when (e:mice-j-p :left)
      (setblock-with-update (floor fistx)
			    (floor fisty)
			    (floor fistz)
			    0
			    0)))
  (collide-with-world)
  (setf onground (nth-value 2 (block-touches *xpos* *ypos* *zpos* player-aabb)))
  (if fly
      (progn
	(setf *xvel* (* *xvel* air-friction))
	(setf *zvel* (* *zvel* air-friction)))
      (cond (onground
	     (setf *xvel* (* *xvel* walking-friction))
	     (setf *zvel* (* *zvel* walking-friction)))
	    (t (setf *xvel* (* *xvel* 0.9))
	       (setf *zvel* (* *zvel* 0.9)))))
  (when (and gravity (not onground))
    (decf *yvel* (* 0.08 (expt tickscale 2))))
  (setf *yvel* (* *yvel* air-friction))
  (let ((cos-pitch (cos *pitch*)))
    (let ((vx (- (* reach (* cos-pitch (cos *yaw*)))))
	  (vy (- (* reach (sin *pitch*))))
	  (vz (- (* reach (* cos-pitch (sin *yaw*))))))
      (multiple-value-bind (frac xclamp yclamp zclamp)
	  (punch-func (+ *xpos* -0.0) (+ *ypos* 0.0) (+ *zpos* -0.0) vx vy vz)
	(declare (ignorable xclamp yclamp zclamp))
	(setf fistx (+ *xpos* (* frac vx))
	      fisty (+ *ypos* (* frac vy))
	      fistz (+ *zpos* (* frac vz)))))))

(defparameter fistx 0.0)
(defparameter fisty 0.0)
(defparameter fistz 0.0)

(defun collide-with-world ()
  (multiple-value-bind (new-x new-y new-z xclamp yclamp zclamp)
      (aabbcc::step-motion #'myafunc
			   *xpos* *ypos* *zpos*
			   *xvel* *yvel* *zvel*)
    (setf *xpos* new-x)
    (setf *ypos* new-y)
    (setf *zpos* new-z)
    (multiple-value-bind (x y z) (aabbcc::clamp-vec
				  *xvel* *yvel* *zvel*
				  xclamp yclamp zclamp)
      (setf *xvel* x)
      (setf *yvel* y)
      (setf *zvel* z))))

(defun goto (x y z)
  (setf *xpos* x
	*ypos* y
	*zpos* z))
(defun look-around ()
  (mouse-looking))

(defun block-aabb ()
  (aabbcc::make-aabb
   :minx 0.0
   :miny 0.0
   :minz 0.0
   :maxx 1.0
   :maxy 1.0
   :maxz 1.0))

(defun player-aabb ()
  (aabbcc::make-aabb
   :minx -0.3
   :miny -1.5
   :minz -0.3
   :maxx 0.3
   :maxy 0.12
   :maxz 0.3))

(defun fist-aabb ()
  (aabbcc::make-aabb
   :minx -0.005
   :miny -0.005
   :minz -0.005
   :maxx 0.005
   :maxy 0.005
   :maxz 0.005))

(defparameter block-aabb (block-aabb))
(defparameter player-aabb (player-aabb))
(defparameter fist-aabb (fist-aabb))

(defparameter reach 5.0)



(defun punch-func (px py pz vx vy vz)
  (blocktocontact fist-aabb px py pz vx vy vz))

(defun myafunc (px py pz vx vy vz)
  (if noclip
      (values 1 nil nil nil)
      (blocktocontact player-aabb px py pz vx vy vz)))

(defun blocktocontact (aabb px py pz vx vy vz)
  (let ((tot-min 1))
    (let (xyz? xy? xz? yz? x? y? z?)
      (multiple-value-bind (minx miny minz maxx maxy maxz) (get-blocks-around-player px py pz)
	(dobox ((x minx maxx)
		(y miny maxy)
		(z minz maxz))
	       (when (aref mc-blocks::iscollidable (world:getblock x y z))
		 (multiple-value-bind (minimum type)
		     (aabbcc::aabb-collide
		      aabb
		      px py pz
		      block-aabb
		      x
		      y
		      z
		      vx vy vz)
		   (unless (> minimum tot-min)
		     (when (< minimum tot-min)
		       (setq tot-min minimum)
		       (null! xyz? xy? yz? xz? x? y? z?))
		     (case type
		       (:xyz (setf xyz? t))
		       (:xy (setf xy? t))
		       (:xz (setf xz? t))
		       (:yz (setf yz? t))
		       (:x (setf x? t))
		       (:y (setf y? t))
		       (:z (setf z? t))))))))
      (multiple-value-bind (xclamp yclamp zclamp)
	  (aabbcc::type-collapser vx vy vz xyz? xy? xz? yz? x? y? z?)
	(values
	 tot-min
	 xclamp yclamp zclamp)))))

(defun block-touches (px py pz aabb)
  (let (x- x+ y- y+ z- z+)
    (multiple-value-bind (minx miny minz maxx maxy maxz) (get-blocks-around-player px py pz)
      (dobox ((x minx maxx)
	      (y miny maxy)
	      (z minz maxz))
	     (when (aref mc-blocks::iscollidable (world:getblock x y z))
	       (multiple-value-bind (i+ i- j+ j- k+ k-)
		   (aabbcc::aabb-contact px py pz aabb x y z block-aabb)
		 (if i+ (setq x+ t))
		 (if i- (setq x- t))
		 (if j+ (setq y+ t))
		 (if j- (setq y- t))
		 (if k+ (setq z+ t))
		 (if k- (setq z- t))))))
    (values x- x+ y- y+ z- z+)))

(defun get-blocks-around-player (px py pz)
  (let ((minx (- (truncate px) 2))
	(miny (- (truncate py) 2))
	(minz (- (truncate pz) 2)))
    (let ((maxx (+ minx 5))
	  (maxy (+ miny 4))
	  (maxz (+ minz 5)))
      (values minx miny minz maxx maxy maxz))))

;;dirty chunks is a list of modified chunks
;;we do not want anyone to see a raw list!
(defparameter dirtychunks nil)
(defun clean-dirty ()
  (setf dirtychunks (q::make-uniq-q)))
(defun dirty-pop ()
  (q::uniq-pop dirtychunks))
(defun dirty-push (item)
  (q::uniq-push item dirtychunks))
(defun block-dirtify (i j k)
  (dirty-push (world:chop (world:chunkhashfunc i k j))))

(defun setblock-with-update (i j k blockid new-light-value)
  (let ((old-blockid (world:getblock i j k)))
    (if (/= blockid old-blockid)
	(let ((old-light-value (world:getlight i j k)))
	  (when (setf (world:getblock i j k) blockid)
	    (when (< new-light-value old-light-value)  
	      (de-light-node i j k))
	    (setf (world:getlight i j k) new-light-value)
	    (sky-de-light-node i j k)
	    (unless (zerop new-light-value)
	      (light-node i j k))
	    (flet ((check (a b c)
		     (light-node (+ i a) (+ j b) (+ k c))
		     (sky-light-node (+ i a) (+ j b) (+ k c))))
	      (check -1 0 0)
	      (check 1 0 0)
	      (check 0 -1 0)
	      (check 0 1 0)
	      (check 0 0 -1)
	      (check 0 0 1))
	    (block-dirtify i j k))))))

(defun plain-setblock (i j k blockid new-light-value)
  (let ((old-blockid (world:getblock i j k)))
    (if (/= blockid old-blockid)
	(when (setf (world:getblock i j k) blockid)
	  (setf (world:getlight i j k) new-light-value)))))

