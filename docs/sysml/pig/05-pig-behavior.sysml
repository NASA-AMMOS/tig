/*
 * How PIG is used at run time: model construction by mars_setup, camera-model
 * creation inside a mission factory, coordinate-system resolution, the
 * per-pixel projection loop of a mosaic program, and the life cycle of a
 * camera model. Sources: mars_support/mars_setup.cc, mars_read_filelist.cc,
 * pig_m20/PigM20.cc, pig/PigMission.cc, prog/marsmap/marsmap.cc.
 */
package PigBehavior {
	private import ScalarValues::*;
	private import PigData::Files::*;
	private import PigData::Geometry::*;
	private import PigData::Calibration::*;
	private import PigData::Products::*;
	private import PigCore::*;

	action def MarsSetup {
		doc /* mars_setup(): turn the INP list and PDF parameters into one file, camera, pointing,
		 * radiometry and brightness model per input, plus the default CS and the surface model. */
		in item inp : InputFileList;
		in item config : MarsConfigTree { doc /* CONFIG_PATH */ }
		in item rsf : RoverStateFile[0..*] ordered { doc /* RSF */ }
		in item navtable : NavFile[0..1] { doc /* NAVTABLE */ }
		in item brtcorr : BrtCorrFile[0..1] { doc /* BRTCORR */ }
		out models : PigFileModel[1..*];
		out cameras : PigCameraModel[1..*];
		out pointings : PigPointingModel[1..*];
		out defaultCS : PigCoordSystem;
		out surface : PigSurfaceModel;
		attribute hasRsf : Boolean;
		attribute navHasSurface : Boolean;
		attribute coordGiven : Boolean;

		first start;
		action getFilelist { doc /* get_filelist(INP): expand list files into image names. */
			in item inp : InputFileList; out item images : VicarImage[1..*] ordered; }
		action selectMission { doc /* PigMission::getMissionObject(first readable input): label MISSION_NAME + host id. */
			in item images : VicarImage[1..*] ordered; out mission : PigMission; }
		decide rsfCheck;
		if hasRsf then readRsf;
		else afterRsf;
		action readRsf { doc /* mars_read_rsf: load RSF / RMC XML into the mission's PigRoverStateManager. */
			in mission : PigMission; in item rsf : RoverStateFile[0..*] ordered; out rsm : PigRoverStateManager; }
		merge afterRsf;
		action readFilelist : ReadInputModels { doc /* mars_read_filelist: per-input model construction. */ }
		action applyNavtable { doc /* mars_apply_navtable: legacy NAVTABLE corrections. */
			in cameras : PigCameraModel[1..*]; in item navtable : NavFile[0..1]; out corrected : PigCameraModel[1..*]; }
		decide csCheck;
		if coordGiven then useCoordParam;
		else useFixedCS;
		action useCoordParam { doc /* COORD / COORD_INDEX / FIXED_SITE select the output CS. */
			in mission : PigMission; out cs : PigCoordSystem; }
		action useFixedCS { doc /* Default CS = mission Fixed frame. */
			in mission : PigMission; out cs : PigCoordSystem; }
		merge afterCs;
		decide surfaceCheck;
		if navHasSurface then surfaceFromNav;
		else surfaceFromMission;
		action surfaceFromNav { doc /* SurfaceModelParams from the nav solution. */
			in item navtable : NavFile[0..1]; out surface : PigSurfaceModel; }
		action surfaceFromMission { doc /* PigSurfaceModel::create(file 0): SURFACE, SURF_COORD, label defaults. */
			in file0 : PigFileModel[1..*]; out surface : PigSurfaceModel; }
		merge afterSurface;
		action returnModels { doc /* Fill the program's files[], camera_in[], pointing_in[], def_cs, surface_model. */
			in cs : PigCoordSystem; in surfaceIn : PigSurfaceModel; out cs0 : PigCoordSystem; out surfaceOut : PigSurfaceModel; }

		bind getFilelist.inp = inp;
		bind readRsf.rsf = rsf;
		bind readFilelist.config = config;
		bind readFilelist.navtable = navtable;
		bind readFilelist.brtcorr = brtcorr;
		bind applyNavtable.navtable = navtable;
		bind surfaceFromNav.navtable = navtable;
		flow getFilelist.images to selectMission.images;
		flow getFilelist.images to readFilelist.images;
		flow selectMission.mission to readRsf.mission;
		flow selectMission.mission to readFilelist.mission;
		flow selectMission.mission to useCoordParam.mission;
		flow selectMission.mission to useFixedCS.mission;
		flow readFilelist.cameras to applyNavtable.cameras;
		flow readFilelist.files to surfaceFromMission.file0;
		flow useCoordParam.cs to returnModels.cs;
		flow useFixedCS.cs to returnModels.cs;
		flow surfaceFromNav.surface to returnModels.surfaceIn;
		flow surfaceFromMission.surface to returnModels.surfaceIn;
		bind models = readFilelist.files;
		bind cameras = applyNavtable.corrected;
		bind pointings = readFilelist.pointings;
		bind defaultCS = returnModels.cs0;
		bind surface = returnModels.surfaceOut;

		succession first start then getFilelist;
		succession first getFilelist then selectMission;
		succession first selectMission then rsfCheck;
		succession first readRsf then afterRsf;
		succession first afterRsf then readFilelist;
		succession first readFilelist then applyNavtable;
		succession first applyNavtable then csCheck;
		succession first useCoordParam then afterCs;
		succession first useFixedCS then afterCs;
		succession first afterCs then surfaceCheck;
		succession first surfaceFromNav then afterSurface;
		succession first surfaceFromMission then afterSurface;
		succession first afterSurface then returnModels;
		succession first returnModels then done;
	}

	action def ReadInputModels {
		doc /* mars_read_filelist(): the order in which PIG models are built for every input image. */
		in item images : VicarImage[1..*] ordered;
		in mission : PigMission;
		in item config : MarsConfigTree;
		in item navtable : NavFile[0..1];
		in item brtcorr : BrtCorrFile[0..1];
		out files : PigFileModel[1..*];
		out cameras : PigCameraModel[1..*];
		out pointings : PigPointingModel[1..*];
		out radiometry : RadiometryModel[0..*];
		out brtCorr : PigBrtCorrModel[0..*];
		attribute moreInputs : Boolean;
		attribute hasRadiometry : Boolean;

		first start;
		merge nextInput;
		action createFileModel { doc /* PigFileModel::create(filename): mission->createFileModel; label read via RTL/lbl_routines. */
			in item image : VicarImage; in mission : PigMission; out file : PigFileModel; }
		action addFileCS { doc /* RoverStateManager::addFileCoordSystems: CS definitions in this label. */
			in file : PigFileModel; out frames : PigCSDefinition[0..*]; }
		action setupCoords { doc /* mars_setup_coords: resolve the default CS for this mission (first input). */
			in file : PigFileModel; out cs : PigCoordSystem; }
		action getPointingCorrections { doc /* mars_get_pointing_corrections: load NAV / nav XML once. */
			in item navtable : NavFile[0..1]; out corrections : PigPointingCorrections[0..1]; }
		action createCamera : CreateCameraModel;
		action createPointing { doc /* mars_create_pointing_model -> mission->createPointingModel(camera, file, POINT_METHOD). */
			in camera : PigCameraModel; in file : PigFileModel; out pointing : PigPointingModel; }
		action pointCamera { doc /* pointing->pointCamera(file): camera initial -> current CS. */
			in pointing : PigPointingModel; in file : PigFileModel; out pointed : PigPointingModel; }
		action applyCorrections { doc /* PigPointingCorrections: replace params or camera model for this image. */
			in pointing : PigPointingModel; in corrections : PigPointingCorrections[0..1]; out corrected : PigPointingModel; }
		decide radCheck;
		if hasRadiometry then createRadiometry;
		else afterRad;
		action createRadiometry { doc /* RadiometryModel::create(file) when RAD is not NONE. */
			in file : PigFileModel; out radiometry : RadiometryModel; }
		merge afterRad;
		action createBrtCorr { doc /* PigBrtCorrModel::createBrtCorrModels(BRTCORR). */
			in file : PigFileModel; in item brtcorr : BrtCorrFile[0..1]; out model : PigBrtCorrModel[0..1]; }
		decide loopCheck;
		if moreInputs then nextInput;
		else done;

		bind getPointingCorrections.navtable = navtable;
		bind createFileModel.image = images;
		bind createFileModel.mission = mission;
		bind createCamera.config = config;
		bind createBrtCorr.brtcorr = brtcorr;
		flow createFileModel.file to addFileCS.file;
		flow createFileModel.file to setupCoords.file;
		flow createFileModel.file to createCamera.file;
		flow createCamera.camera to createPointing.camera;
		flow createFileModel.file to createPointing.file;
		flow createPointing.pointing to pointCamera.pointing;
		flow createFileModel.file to pointCamera.file;
		flow pointCamera.pointed to applyCorrections.pointing;
		flow getPointingCorrections.corrections to applyCorrections.corrections;
		flow createFileModel.file to createRadiometry.file;
		flow createFileModel.file to createBrtCorr.file;
		bind files = createFileModel.file;
		bind cameras = createCamera.camera;
		bind pointings = applyCorrections.corrected;
		bind radiometry = createRadiometry.radiometry;
		bind brtCorr = createBrtCorr.model;

		succession first start then getPointingCorrections;
		succession first getPointingCorrections then nextInput;
		succession first nextInput then createFileModel;
		succession first createFileModel then addFileCS;
		succession first addFileCS then setupCoords;
		succession first setupCoords then createCamera;
		succession first createCamera then createPointing;
		succession first createPointing then pointCamera;
		succession first pointCamera then applyCorrections;
		succession first applyCorrections then radCheck;
		succession first createRadiometry then afterRad;
		succession first afterRad then createBrtCorr;
		succession first createBrtCorr then loopCheck;
	}

	action def CreateCameraModel {
		doc /* PigMission::createCameraModel (PigM20 shown; other missions follow the same pattern). */
		in file : PigFileModel;
		in item config : MarsConfigTree { doc /* camera_mapping XML and calibration models */ }
		out camera : PigCameraModel;
		attribute useLabel : Boolean;
		attribute foundInLabel : Boolean;

		first start;
		action getInstrumentId { doc /* INSTRUMENT_ID and frame type from the label; reject unknown instruments. */
			in file : PigFileModel; out instrumentId : String; }
		action buildConstruction { doc /* Subframe and downsampling into the construction string. */
			in file : PigFileModel; out construction : String; }
		action buildSubtype { doc /* Filter, focus and temperature into the subtype string. */
			in file : PigFileModel; out subtype : String; }
		decide sourceCheck;
		if useLabel then readLabelModel;
		else lookupMapper;
		action readLabelModel { doc /* createFromLabel: GEOMETRIC_CAMERA_MODEL group (named or instance 1). */
			in file : PigFileModel; out camera : PigCameraModel[0..1]; }
		decide labelFound;
		if foundInLabel then modelReady;
		else lookupMapper;
		action lookupMapper { doc /* PigCameraMapper: serial number / instrument id -> calibration entry. */
			in instrumentId : String; in item config : MarsConfigTree; out mapEntry : PigCameraMapEntry; }
		action readCalibration { doc /* readFromFile(findFile(calibration name)): CAHV/CAHVOR/CAHVORE/PSPH. */
			in mapEntry : PigCameraMapEntry; in construction : String; in subtype : String;
			in item config : MarsConfigTree; out camera : PigCameraModel; }
		action interpolate { doc /* Interpolate calibration over focus / zoom / temperature when tabulated. */
			in camera : PigCameraModel; out interpolated : PigCameraModel; }
		merge modelReady;
		action setInitialCS { doc /* Initial CS = instrument frame from the mission. */
			in camera : PigCameraModel; out initialized : PigCameraModel; }

		bind getInstrumentId.file = file;
		bind buildConstruction.file = file;
		bind buildSubtype.file = file;
		bind readLabelModel.file = file;
		bind lookupMapper.config = config;
		bind readCalibration.config = config;
		flow getInstrumentId.instrumentId to lookupMapper.instrumentId;
		flow lookupMapper.mapEntry to readCalibration.mapEntry;
		flow buildConstruction.construction to readCalibration.construction;
		flow buildSubtype.subtype to readCalibration.subtype;
		flow readCalibration.camera to interpolate.camera;
		flow readLabelModel.camera to setInitialCS.camera;
		flow interpolate.interpolated to setInitialCS.camera;
		bind camera = setInitialCS.initialized;

		succession first start then getInstrumentId;
		succession first getInstrumentId then buildConstruction;
		succession first buildConstruction then buildSubtype;
		succession first buildSubtype then sourceCheck;
		succession first readLabelModel then labelFound;
		succession first lookupMapper then readCalibration;
		succession first readCalibration then interpolate;
		succession first interpolate then modelReady;
		succession first modelReady then setInitialCS;
		succession first setInitialCS then done;
	}

	action def ResolveCoordSystem {
		doc /* PigMission::getCoordSystem(PigCSReference): find or build a frame and its chain to Fixed. */
		in ident : PigCSReference;
		in rsm : PigRoverStateManager;
		out cs : PigCoordSystem;
		attribute cached : Boolean;
		attribute found : Boolean;
		attribute referenceIsFixed : Boolean;

		first start;
		decide cacheCheck;
		if cached then fromCache;
		else lookupSolution;
		action fromCache { doc /* Return the PigCoordSystem already built for this identity. */
			in ident : PigCSReference; out cs : PigCoordSystem; }
		action lookupSolution { doc /* RoverStateManager::findSolution: best PigCSDefinition by SOLUTION_ID priority. */
			in ident : PigCSReference; in rsm : PigRoverStateManager; out definition : PigCSDefinition[0..1]; }
		decide foundCheck;
		if found then fixedCheck;
		else defaultCS;
		action resolveReference { doc /* Recursively resolve the definition's reference frame. */
			in definition : PigCSDefinition; out reference : PigCoordSystem; }
		decide fixedCheck;
		if referenceIsFixed then buildCS;
		else resolveReference;
		action buildCS { doc /* New PigCoordSystem(offset, quaternion, reference); compute composite to Fixed. */
			in definition : PigCSDefinition; in reference : PigCoordSystem[0..1]; out cs : PigCoordSystem; }
		action defaultCS { doc /* Fall back to the mission default for the frame (warns). */
			in ident : PigCSReference; out cs : PigCoordSystem; }
		merge ready;
		action returnCS { doc /* Add a newly built frame to the mission cache and return it. */
			in cs : PigCoordSystem; out result : PigCoordSystem; }

		bind fromCache.ident = ident;
		bind lookupSolution.ident = ident;
		bind lookupSolution.rsm = rsm;
		bind defaultCS.ident = ident;
		flow lookupSolution.definition to resolveReference.definition;
		flow lookupSolution.definition to buildCS.definition;
		flow resolveReference.reference to buildCS.reference;
		flow fromCache.cs to returnCS.cs;
		flow buildCS.cs to returnCS.cs;
		flow defaultCS.cs to returnCS.cs;
		bind cs = returnCS.result;

		succession first start then cacheCheck;
		succession first fromCache then ready;
		succession first lookupSolution then foundCheck;
		succession first resolveReference then buildCS;
		succession first buildCS then ready;
		succession first defaultCS then ready;
		succession first ready then returnCS;
		succession first returnCS then done;
	}

	action def ProjectMosaicPixel {
		doc /* marsmap inner loop for one output pixel (cylindrical/polar/vertical projections). */
		in outPixel : ImageCoordinate;
		in surface : PigSurfaceModel;
		in cameras : PigCameraModel[1..*];
		in item inputs : VicarImage[1..*] ordered;
		out dn : Real;
		attribute hit : Boolean;
		attribute inside : Boolean;
		attribute moreInputs : Boolean;

		first start;
		action outputToRay { doc /* Projection (az, el or x, y) -> ray in the output CS. */
			in outPixel : ImageCoordinate; out ray : Ray; }
		action intersectSurface { doc /* surface->intersectRay(ray): hit point or infinity. */
			in ray : Ray; in surface : PigSurfaceModel; out point : PigPoint; }
		decide hitCheck;
		if hit then convertToInputCS;
		else writeDn;
		action convertToInputCS { doc /* PigCoordSystem::convertPoint into each input camera's CS. */
			in point : PigPoint; out inputPoint : PigPoint; }
		merge nextInput;
		action projectToImage { doc /* camera->XYZtoLS(point): line/sample in the input. */
			in inputPoint : PigPoint; in cameras : PigCameraModel[1..*]; out inPixel : ImageCoordinate; }
		decide insideCheck;
		if inside then sampleAndCorrect;
		else moreCheck;
		action sampleAndCorrect { doc /* Interpolate DN, apply RadiometryModel and PigBrtCorrModel. */
			in inPixel : ImageCoordinate; in item inputs : VicarImage[1..*] ordered; out sample : Real; }
		decide moreCheck;
		if moreInputs then nextInput;
		else writeDn;
		action writeDn { doc /* Write the output DN (first-overlap or blended; 0 when nothing hit). */
			in sample : Real[0..1]; out dn : Real; }

		bind outputToRay.outPixel = outPixel;
		bind intersectSurface.surface = surface;
		bind projectToImage.cameras = cameras;
		bind sampleAndCorrect.inputs = inputs;
		flow outputToRay.ray to intersectSurface.ray;
		flow intersectSurface.point to convertToInputCS.point;
		flow convertToInputCS.inputPoint to projectToImage.inputPoint;
		flow projectToImage.inPixel to sampleAndCorrect.inPixel;
		flow sampleAndCorrect.sample to writeDn.sample;
		bind dn = writeDn.dn;

		succession first start then outputToRay;
		succession first outputToRay then intersectSurface;
		succession first intersectSurface then hitCheck;
		succession first convertToInputCS then nextInput;
		succession first nextInput then projectToImage;
		succession first projectToImage then insideCheck;
		succession first sampleAndCorrect then writeDn;
		succession first writeDn then done;
	}

	action def RunVisorProgramInTig {
		doc /* tig <program> ...: from the host CLI to PIG inside the container. */
		in args : String[1..*] ordered { doc /* program name and PDF arguments as typed on the host */ }
		in item hostList : InputFileList { doc /* INP list file with host paths */ }
		out item product : MarsProduct;

		first start;
		action resolveTool { doc /* tig-cli resolves the VICAR/VISOR tool name (tig-shim symlinks). */
			in args : String[1..*] ordered; out program : String; }
		action translatePaths { doc /* Host paths in arguments and list files -> container paths. */
			in args : String[1..*] ordered; in item hostList : InputFileList;
			out containerArgs : String[1..*] ordered; out item containerList : InputFileList; }
		action runContainer { doc /* Start or reuse the TIG container with the workspace mounted. */
			in program : String; in containerArgs : String[1..*] ordered; out command : String; }
		action vicarRun { doc /* /usr/local/libexec/vicar-run: source VICAR env, set MARS_CONFIG_PATH. */
			in command : String; out item config : MarsConfigTree; }
		action parseParams { doc /* Shell-VICAR/TAE parse the program's PDF parameters. */
			in command : String; in item containerList : InputFileList; out item inp : InputFileList; }
		action setup : MarsSetup;
		action process { doc /* Program-specific processing on PIG models (e.g. ProjectMosaicPixel). */
			in models : PigFileModel[1..*]; in cameras : PigCameraModel[1..*]; in surface : PigSurfaceModel;
			in defaultCS : PigCoordSystem; out item raw : MarsProduct; }
		action writeLabels { doc /* PigLabelModel writes geometry labels on each output product. */
			in item raw : MarsProduct; in models : PigFileModel[1..*]; out item labelled : MarsProduct; }

		bind resolveTool.args = args;
		bind translatePaths.args = args;
		bind translatePaths.hostList = hostList;
		flow resolveTool.program to runContainer.program;
		flow translatePaths.containerArgs to runContainer.containerArgs;
		flow runContainer.command to vicarRun.command;
		flow runContainer.command to parseParams.command;
		flow translatePaths.containerList to parseParams.containerList;
		flow parseParams.inp to setup.inp;
		flow vicarRun.config to setup.config;
		flow setup.models to process.models;
		flow setup.cameras to process.cameras;
		flow setup.surface to process.surface;
		flow setup.defaultCS to process.defaultCS;
		flow process.raw to writeLabels.raw;
		flow setup.models to writeLabels.models;
		bind product = writeLabels.labelled;

		succession first start then resolveTool;
		succession first resolveTool then translatePaths;
		succession first translatePaths then runContainer;
		succession first runContainer then vicarRun;
		succession first vicarRun then parseParams;
		succession first parseParams then setup;
		succession first setup then process;
		succession first process then writeLabels;
		succession first writeLabels then done;
	}

	state def CameraModelLifecycle {
		doc /* Which parameter set of a PigCameraModel is current. */
		entry; then calibrated;
		state calibrated { doc /* Initial parameters, in the instrument frame. */ }
		state pointed { doc /* Current = initial moved by the pointing model. */ }
		state corrected { doc /* Pointing parameters or model replaced from a nav solution. */ }
		state adjusting { doc /* A nav solver is perturbing the adjustable parameters. */ }
		transition pointCamera first calibrated then pointed;
		transition applyNav first pointed then corrected;
		transition startSolve first pointed then adjusting;
		transition startSolveCorrected first corrected then adjusting;
		transition converge first adjusting then corrected;
		transition resetCameraLocation first pointed then calibrated;
	}

	state def FileModelLifecycle {
		doc /* PigFileModel keeps few VICAR units open; it closes and reopens on demand. */
		entry; then closed;
		state closed;
		state openRead { doc /* zvopen(..., "OPEN_ACT", "SA") for pixel or label access. */ }
		transition openFile first closed then openRead;
		transition closeFile first openRead then closed;
	}
}
