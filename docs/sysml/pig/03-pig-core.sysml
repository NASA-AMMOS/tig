/*
 * PIG core library (vos/mars/src/sub/pig, pig_xml; headers vos/mars/inc).
 * One part def per C++ class; C++ inheritance is SysML specialization,
 * pointer members are reference parts, and the public virtual methods that
 * matter to callers are owned actions.
 */
package PigCore {
	private import ScalarValues::*;
	private import PigData::Geometry::*;
	private import PigData::Identity::*;
	private import PigData::Files::*;
	private import PigData::Calibration::*;

	enum def PigMsgSeverity {
		doc /* printMsg severities; output goes through a replaceable PigMsgFunction (default zvmessage). */
		enum PigMsgDebug; enum PigMsgInfo; enum PigMsgWarning; enum PigMsgError; enum PigMsgFatal;
	}

	// ------------------------------------------------------------------
	// Common bases
	// ------------------------------------------------------------------
	abstract part def PigModelBase {
		doc /* Root of every PIG model. Supplies messaging (printMsg/printFatal/printWarning), parameter
		 * access through a replaceable PigParamFunction (default VICAR zvp/zvparmd, so PIG can run
		 * outside TAE), and calibration lookup (findFile over CONFIG_PATH, default $MARS_CONFIG_PATH). */
		attribute modelName : String;
		attribute configPath : String = "$MARS_CONFIG_PATH";
		attribute maxFilenameSize : Integer = 250;
		ref item calibration : MarsConfigTree[0..1];
		action printMsg { in msg : String; in severity : PigMsgSeverity; }
		action getParam { in name : String; out count : Integer; }
		action findFile { in relativeName : String; out fullPath : String; }
	}

	abstract part def PigAdjustable {
		doc /* Mixin for models whose parameters a solver can perturb (marsnav, marsnav2, marsbrt):
		 * pointing models, coordinate systems and surfaces. */
		attribute pointingParamCount : Integer;
		action getPointingParameters { out params : Real[0..*] ordered; }
		action setPointingParameters { in params : Real[0..*] ordered; }
		action getPointingErrorEstimate { out errors : Real[0..*] ordered; }
		action getPointingParamName { in index : Integer; out name : String; }
	}

	// ------------------------------------------------------------------
	// Mission abstract factory
	// ------------------------------------------------------------------
	abstract part def PigMission :> PigModelBase {
		doc /* Abstract factory and per-mission singleton. getMissionObject(filename|PigFileModel|name)
		 * reads the mission and host id from the label (PigGetMission) and returns the cached instance
		 * for that MissionKey; every other model's static create() delegates here. */
		attribute key : MissionKey;
		attribute defaultSurfaceType : String;
		ref part fixedCS : PigCoordSystem[0..1];
		ref part roverStateManager : PigRoverStateManager[0..1];
		ref part cameraMapper : PigCameraMapper[0..1];

		action getMissionObject { in filename : String; out mission : PigMission; }
		action createFileModel { in filename : String; in unit : Integer; out file : PigFileModel; }
		action createCameraModel { in file : PigFileModel; in special : String[0..1]; out camera : PigCameraModel; }
		action createPointingModel { in camera : PigCameraModel; in file : PigFileModel; in pointMethod : String[0..1]; out pointing : PigPointingModel; }
		action createSurfaceModel { in file : PigFileModel; out surface : PigSurfaceModel; }
		action createRadiometryModel { in file : PigFileModel; out radiometry : RadiometryModel; }
		action createLabelModel { in unit : Integer; out labelModel : PigLabelModel; }
		action createColorModel { in file : PigFileModel; out color : PigColorModel; }
		action getCoordSystem { in ident : PigCSReference; out cs : PigCoordSystem; }
		action getFixedCS { out cs : PigCoordSystem; }
		action getBorders { in file : PigFileModel; out sl : Integer; out ss : Integer; out el : Integer; out es : Integer; }
	}

	// ------------------------------------------------------------------
	// Files and labels
	// ------------------------------------------------------------------
	part def PigFileModel :> PigModelBase {
		doc /* Wraps one input image: opens/closes it through RTL (zvopen/zvclose, reopened on demand to
		 * stay under the open-unit limit), caches the label groups via p2 lbl_routines and exposes
		 * geometry metadata (instrument id, frame, RMC, borders, FOV, CS definitions, camera-model label). */
		attribute filename : String;
		attribute unit : Integer;
		attribute instrumentId : String;
		attribute missionName : String;
		attribute isOpen : Boolean;
		ref item image : VicarImage;
		action openFile;
		action closeFile;
		action getRoverMotionCounter { out rmc : RoverMotionCounter; }
		action checkFOV { in camera : PigCameraModel; in direction : PigVector; out inFov : Boolean; }
	}

	part def PigLabelModel :> PigModelBase {
		doc /* Writes the output product's geometry labels (open-for-write unit): writeCM, writeCS,
		 * writePointingModel, setMapCyl/setMapPolar/setMapVert/setMapSin, setXYZ, setUVW, setDisparity,
		 * setSlope, setRough, setRange, setReach, setMask ... Mission subclasses add their own groups. */
		attribute outputUnit : Integer;
		ref item product : MarsProduct;
		action writeProductLabel { in productType : ProductType; in inputs : PigFileModel[1..*]; }
		action writeCM { in camera : PigCameraModel; in cs : PigCoordSystem; }
		action writeCS { in cs : PigCoordSystem; }
	}

	// ------------------------------------------------------------------
	// Coordinate systems
	// ------------------------------------------------------------------
	part def PigCSReference {
		doc /* Names a coordinate system without defining it: frame, RMC, solution id, instrument. */
		attribute identity : CoordSystemIdentity;
	}

	abstract part def PigSolutionItem {
		doc /* An item carried by a PigSolutionManager, with solution id and priority. */
		attribute solutionId : String;
		attribute priority : Integer;
	}

	part def PigCSDefinition :> PigSolutionItem {
		doc /* Defines a frame: its identity, the reference frame it is relative to, offset and quaternion. */
		part ident : PigCSReference;
		part referenceIdent : PigCSReference;
		attribute offset : PigVector;
		attribute orientation : PigQuaternion;
	}

	part def PigCoordSystem :> PigModelBase, PigAdjustable {
		doc /* A live frame in a chain that ends at the mission Fixed frame (normally the lowest Site).
		 * Holds offset and quaternion to its reference frame plus a cached composite to Fixed, so
		 * convertPoint/convertVector/convertAzEl/convertQuat between any two frames go through Fixed.
		 * Adjustable with 6 parameters (3 rotation, 3 translation). */
		attribute identity : CoordSystemIdentity;
		attribute offsetToReference : PigVector;
		attribute quatToReference : PigQuaternion;
		attribute offsetToFixed : PigVector;
		attribute quatToFixed : PigQuaternion;
		attribute azimuthDirection : Integer;
		attribute elevationDirection : Integer;
		attribute :>> pointingParamCount default = 6;
		ref part referenceCS : PigCoordSystem[0..1];
		ref part mission : PigMission;
		action convertPoint { in point : PigPoint; in fromCS : PigCoordSystem; out result : PigPoint; }
		action convertVector { in vector : PigVector; in fromCS : PigCoordSystem; out result : PigVector; }
		action convertAzEl { in azel : AzEl; in fromCS : PigCoordSystem; out result : AzEl; }
		action reparent { in newReference : PigCoordSystem; }
	}

	abstract part def PigSolutionManager :> PigModelBase {
		doc /* Holds prioritised solutions read from XML (Xerces) and labels; findSolution picks the
		 * best match for a key, honouring SOLUTION_ID and priority lists. */
		attribute solutionIdOrder : String[0..*] ordered;
		ref part items : PigSolutionItem[0..*];
		action findSolution { in ident : PigCSReference; out item : PigSolutionItem[0..1]; }
	}

	part def PigRoverStateManager :> PigSolutionManager {
		doc /* Rover-state database: CS definitions from RSF/RMC XML files (mars_read_rsf), from every
		 * input label (addFileCoordSystems) and from mission defaults; per-mission subclasses know frame
		 * names and RMC index meanings. Owned by the PigMission. */
		ref item rsfFiles : RoverStateFile[0..*];
		ref part definitions : PigCSDefinition[0..*] :>> items;
		action readRSF { in file : RoverStateFile; }
		action addFileCoordSystems { in file : PigFileModel; }
	}

	// ------------------------------------------------------------------
	// Camera models
	// ------------------------------------------------------------------
	abstract part def PigCameraModel :> PigModelBase {
		doc /* Geometric camera model. Keeps the calibration (initial) and pointed (current) parameters,
		 * each with its coordinate system; a PigPointingModel moves it from initial to current.
		 * Projects image coordinates to rays (LStoLookVector) and points to image (XYZtoLS).
		 * create() goes through PigMission::createCameraModel. */
		attribute cameraType : String;
		attribute instrumentName : String;
		attribute calibrationFile : String[0..1];
		ref part initialCS : PigCoordSystem;
		ref part currentCS : PigCoordSystem;
		ref part pointingModel : PigPointingModel[0..1];
		ref item modelFile : CameraModelFile[0..1];
		action readFromFile { in filename : String; in cs : PigCoordSystem; }
		action readFromLabel { in file : PigFileModel; in instance : Integer; }
		action writeToFile { in filename : String; }
		action LStoLookVector { in coord : ImageCoordinate; in cs : PigCoordSystem; out ray : Ray; }
		action XYZtoLS { in point : PigPoint; in infinity : Boolean; in cs : PigCoordSystem; out coord : ImageCoordinate; }
		action moveCamera { in fromLocation : PigPoint; in fromOrientation : PigQuaternion; in toLocation : PigPoint; in toOrientation : PigQuaternion; }
		action resetCameraLocation;
		action scaleCamera { in xFactor : Real; in yFactor : Real; }
		action shiftCamera { in dx : Real; in dy : Real; }
	}
	part def PigCAHV :> PigCameraModel { doc /* Linear CAHV model (C, A, H, V vectors) over p2 cmod_cahv. */ attribute :>> cameraType default = "CAHV"; }
	part def PigCAHVOR :> PigCAHV { doc /* CAHV plus radial distortion (O, R) over p2 cmod_cahvor. */ attribute :>> cameraType default = "CAHVOR"; }
	part def PigCAHVORE :> PigCAHVOR { doc /* CAHVOR plus entrance-pupil terms (E, linearity) for fisheye lenses, p2 cmod_cahvore. */ attribute :>> cameraType default = "CAHVORE"; }
	part def PigPSPH :> PigCameraModel { doc /* Planospheric model for stereo-rectified / panoramic products. */ attribute :>> cameraType default = "PSPH"; }

	part def PigCameraMapper :> PigModelBase {
		doc /* Reads <mission>_camera_mapping.xml and maps serial number, instrument id and filter to a
		 * PigCameraMapEntry (calibration file name, camera type, filter/focus/temperature interpolation). */
		ref item mappingFile : CameraMappingFile;
		part entries : PigCameraMapEntry[0..*];
		action findFromSerial { in serial : String; out mapEntry : PigCameraMapEntry[0..1]; }
		action findFromID { in instrumentId : String; out mapEntry : PigCameraMapEntry[0..1]; }
	}
	part def PigCameraMapEntry {
		attribute serialNumber : String;
		attribute instrumentId : String;
		attribute cameraType : String;
		attribute calibrationFile : String;
	}

	// ------------------------------------------------------------------
	// Pointing models
	// ------------------------------------------------------------------
	abstract part def PigPointingModel :> PigModelBase, PigAdjustable {
		doc /* Aims one camera model: pointCamera(file) reads the commanded/telemetered pointing from the
		 * label (or POINT_METHOD source), moves the camera into its current CS, and exposes the
		 * articulation as adjustable parameters for nav solvers. Bidirectionally linked with the camera. */
		attribute pointMethod : String[0..1];
		ref part camera : PigCameraModel;
		ref part cs : PigCoordSystem;
		ref item pointParams : PointParamsFile[0..1];
		action pointCamera { in file : PigFileModel; }
		action getCameraPosition { in cs : PigCoordSystem; out position : PigPoint; }
		action getCameraOrientation { in cs : PigCoordSystem; out orientation : PigVector; }
		action getCameraTwist { out twist : Real; }
	}
	part def PigPointBodyFixedCamera :> PigPointingModel { doc /* No articulation: camera rigidly mounted on the body. */ attribute :>> pointingParamCount default = 0; }
	part def PigPointPanTiltCamera :> PigPointingModel { doc /* Azimuth/elevation head (mast, PMA). */ attribute :>> pointingParamCount default = 2; }
	part def PigPointTwoPivotCamera :> PigPointPanTiltCamera { doc /* Pan-tilt with separate pivot points. */ }
	part def PigPointCamera7dof :> PigPointingModel { doc /* Free position (3) + quaternion (4) camera, e.g. arm cameras. */ attribute :>> pointingParamCount default = 7; }
	part def PigPointCamera6dof :> PigPointCamera7dof { doc /* Position (3) + Euler orientation (3). */ attribute :>> pointingParamCount default = 6; }

	// ------------------------------------------------------------------
	// Surface models
	// ------------------------------------------------------------------
	abstract part def PigSurfaceModel :> PigModelBase, PigAdjustable {
		doc /* Terrain model in a coordinate system. intersectRay returns hit point and code (hit, miss,
		 * infinity); getRay builds the ray used by mosaics when the surface is behind the camera.
		 * Created by PigMission::createSurfaceModel from label/SURFACE parameters or a nav file. */
		attribute surfaceType : String;
		ref part cs : PigCoordSystem;
		action intersectRay { in ray : Ray; out hit : PigPoint; out code : Integer; }
		action countIntersections { in ray : Ray; out count : Integer; }
		action writeToLabel { in labelModel : PigLabelModel; }
	}
	part def PigSurfacePlane :> PigSurfaceModel { doc /* Plane: normal + ground point (SURF_NORMAL, SURF_GROUND). */ attribute normal : PigVector; attribute ground : PigPoint; }
	part def PigSurfaceSphere :> PigSurfaceModel { doc /* Sphere centered on a point. */ attribute center : PigPoint; attribute radius : Real; }
	part def PigSurfaceSphere2 :> PigSurfaceModel { doc /* Sphere variant that intersects the far side. */ }
	part def PigSurfaceSphere1 :> PigSurfaceSphere2 { doc /* Near-side variant of Sphere2. */ }
	part def PigSurfaceInfinity :> PigSurfaceModel { doc /* Every ray hits at infinity (pure rotation mosaics). */ }
	part def PigSurfaceMesh :> PigSurfaceModel { doc /* OBJ mesh intersected with Embree (built when USES_PIG_MESH). */ ref item mesh : MeshFile; }

	// ------------------------------------------------------------------
	// Radiometry, brightness and colour
	// ------------------------------------------------------------------
	abstract part def RadiometryModel :> PigModelBase {
		doc /* Radiometric correction of one input (RAD parameter): flat field, dark current, exposure
		 * and responsivity, giving DN-scaled radiance; mission subclasses supply calibration lookup. */
		ref part file : PigFileModel;
		ref item flatField : FlatFieldFile[0..1];
		attribute responsivity : Real[0..*];
		attribute exposureTime : Real;
		action applyCorrection { in image : VicarImage; out corrected : VicarImage; }
	}
	part def PigBrtCorrModel :> PigModelBase {
		doc /* Per-image brightness correction (BRTCORR file from marsbrt) applied after radiometry. */
		ref item brtCorrFile : BrtCorrFile[0..1];
		action applyCorrection { in dn : Real; out corrected : Real; }
	}
	part def PigBrtCorrLinear :> PigBrtCorrModel { attribute add : Real; attribute mult : Real; }
	part def PigBrtCorrHsiLin :> PigBrtCorrLinear { doc /* Linear correction in HSI space for colour mosaics. */ }

	abstract part def PigColorConverter { doc /* One colour-space transform. */ }
	part def PigColorConverterMatrix :> PigColorConverter;
	part def PigColorConverterRADtoiRGB :> PigColorConverter;
	part def PigColorConverterXYZtosRGB :> PigColorConverter;
	part def PigColorConverterXYZtoxyY :> PigColorConverter;
	part def PigColorModel :> PigModelBase {
		doc /* Colour processing for colour cameras: chooses converters, illuminant and scaling. */
		part converters : PigColorConverter[0..*];
	}

	// ------------------------------------------------------------------
	// Pointing corrections (nav solutions)
	// ------------------------------------------------------------------
	part def PigPCItem :> PigSolutionItem { doc /* One image's corrected pointing parameters or camera model. */ }
	part def PigSurfaceModelParams :> PigSolutionItem { doc /* Surface model stored in a nav solution. */ }
	part def PigPointingCorrections :> PigSolutionManager {
		doc /* Reads NAVTABLE/nav XML from marsnav/marsnav2 and applies corrected pointing parameters or
		 * replacement camera models to each input (mars_get_pointing_corrections). */
		ref item navFiles : NavFile[0..*];
		ref part corrections : PigPCItem[0..*] :>> items;
		ref part surfaceParams : PigSurfaceModelParams[0..1];
		action applyTo { in pointing : PigPointingModel; in file : PigFileModel; }
	}
}
