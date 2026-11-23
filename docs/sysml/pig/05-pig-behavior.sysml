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
	private import PigCore::*;

	action def MarsSetup {
		doc /* mars_setup(): turn the INP list and PDF parameters into one file, camera, pointing,
		 * radiometry and brightness model per input, plus the default CS and the surface model. */
		in item inp : InputFileList;
		out item models : PigFileModel[1..*];
		attribute hasRsf : Boolean;
		attribute navHasSurface : Boolean;
		attribute coordGiven : Boolean;

		first start;
		action getFilelist { doc /* get_filelist(INP): expand list files into image names. */ }
		action selectMission { doc /* PigMission::getMissionObject(first readable input): label MISSION_NAME + host id. */ }
		decide rsfCheck;
		if hasRsf then readRsf;
		else afterRsf;
		action readRsf { doc /* mars_read_rsf: load RSF / RMC XML into the mission's PigRoverStateManager. */ }
		merge afterRsf;
		action readFilelist : ReadInputModels { doc /* mars_read_filelist: per-input model construction. */ }
		action applyNavtable { doc /* mars_apply_navtable: legacy NAVTABLE corrections. */ }
		decide csCheck;
		if coordGiven then useCoordParam;
		else useFixedCS;
		action useCoordParam { doc /* COORD / COORD_INDEX / FIXED_SITE select the output CS. */ }
		action useFixedCS { doc /* Default CS = mission Fixed frame. */ }
		merge afterCs;
		decide surfaceCheck;
		if navHasSurface then surfaceFromNav;
		else surfaceFromMission;
		action surfaceFromNav { doc /* SurfaceModelParams from the nav solution. */ }
		action surfaceFromMission { doc /* PigSurfaceModel::create(file 0): SURFACE, SURF_COORD, label defaults. */ }
		merge afterSurface;

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
		succession first afterSurface then done;
	}

	action def ReadInputModels {
		doc /* mars_read_filelist(): the order in which PIG models are built for every input image. */
		attribute moreInputs : Boolean;
		attribute hasRadiometry : Boolean;

		first start;
		merge nextInput;
		action createFileModel { doc /* PigFileModel::create(filename): mission->createFileModel; label read via RTL/lbl_routines. */ }
		action addFileCS { doc /* RoverStateManager::addFileCoordSystems: CS definitions in this label. */ }
		action setupCoords { doc /* mars_setup_coords: resolve the default CS for this mission (first input). */ }
		action getPointingCorrections { doc /* mars_get_pointing_corrections: load NAV / nav XML once. */ }
		action createCamera : CreateCameraModel;
		action createPointing { doc /* mars_create_pointing_model -> mission->createPointingModel(camera, file, POINT_METHOD). */ }
		action pointCamera { doc /* pointing->pointCamera(file): camera initial -> current CS. */ }
		action applyCorrections { doc /* PigPointingCorrections: replace params or camera model for this image. */ }
		decide radCheck;
		if hasRadiometry then createRadiometry;
		else afterRad;
		action createRadiometry { doc /* RadiometryModel::create(file) when RAD is not NONE. */ }
		merge afterRad;
		action createBrtCorr { doc /* PigBrtCorrModel::createBrtCorrModels(BRTCORR). */ }
		decide loopCheck;
		if moreInputs then nextInput;
		else done;

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
		out camera : PigCameraModel;
		attribute useLabel : Boolean;
		attribute foundInLabel : Boolean;

		first start;
		action getInstrumentId { doc /* INSTRUMENT_ID and frame type from the label; reject unknown instruments. */ }
		action buildConstruction { doc /* Subframe and downsampling into the construction string. */ }
		action buildSubtype { doc /* Filter, focus and temperature into the subtype string. */ }
		decide sourceCheck;
		if useLabel then readLabelModel;
		else lookupMapper;
		action readLabelModel { doc /* createFromLabel: GEOMETRIC_CAMERA_MODEL group (named or instance 1). */ }
		decide labelFound;
		if foundInLabel then modelReady;
		else lookupMapper;
		action lookupMapper { doc /* PigCameraMapper: serial number / instrument id -> calibration entry. */ }
		action readCalibration { doc /* readFromFile(findFile(calibration name)): CAHV/CAHVOR/CAHVORE/PSPH. */ }
		action interpolate { doc /* Interpolate calibration over focus / zoom / temperature when tabulated. */ }
		merge modelReady;
		action setInitialCS { doc /* Initial CS = instrument frame from the mission. */ }

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
		out cs : PigCoordSystem;
		attribute cached : Boolean;
		attribute found : Boolean;
		attribute referenceIsFixed : Boolean;

		first start;
		decide cacheCheck;
		if cached then ready;
		else lookupSolution;
		action lookupSolution { doc /* RoverStateManager::findSolution: best PigCSDefinition by SOLUTION_ID priority. */ }
		decide foundCheck;
		if found then fixedCheck;
		else defaultCS;
		action resolveReference { doc /* Recursively resolve the definition's reference frame. */ }
		decide fixedCheck;
		if referenceIsFixed then buildCS;
		else resolveReference;
		action buildCS { doc /* New PigCoordSystem(offset, quaternion, reference); compute composite to Fixed. */ }
		action defaultCS { doc /* Fall back to the mission default for the frame (warns). */ }
		merge ready;

		succession first start then cacheCheck;
		succession first lookupSolution then foundCheck;
		succession first resolveReference then buildCS;
		succession first buildCS then ready;
		succession first defaultCS then ready;
		succession first ready then done;
	}

	action def ProjectMosaicPixel {
		doc /* marsmap inner loop for one output pixel (cylindrical/polar/vertical projections). */
		attribute hit : Boolean;
		attribute inside : Boolean;
		attribute moreInputs : Boolean;

		first start;
		action outputToRay { doc /* Projection (az, el or x, y) -> ray in the output CS. */ }
		action intersectSurface { doc /* surface->intersectRay(ray): hit point or infinity. */ }
		decide hitCheck;
		if hit then convertToInputCS;
		else writeDn;
		action convertToInputCS { doc /* PigCoordSystem::convertPoint into each input camera's CS. */ }
		merge nextInput;
		action projectToImage { doc /* camera->XYZtoLS(point): line/sample in the input. */ }
		decide insideCheck;
		if inside then sampleAndCorrect;
		else moreCheck;
		action sampleAndCorrect { doc /* Interpolate DN, apply RadiometryModel and PigBrtCorrModel. */ }
		decide moreCheck;
		if moreInputs then nextInput;
		else writeDn;
		action writeDn { doc /* Write the output DN (first-overlap or blended). */ }

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
		first start;
		action resolveTool { doc /* tig-cli resolves the VICAR/VISOR tool name (tig-shim symlinks). */ }
		action translatePaths { doc /* Host paths in arguments and list files -> container paths. */ }
		action runContainer { doc /* Start or reuse the TIG container with the workspace mounted. */ }
		action vicarRun { doc /* /usr/local/libexec/vicar-run: source VICAR env, set MARS_CONFIG_PATH. */ }
		action parseParams { doc /* Shell-VICAR/TAE parse the program's PDF parameters. */ }
		action setup : MarsSetup;
		action process { doc /* Program-specific processing on PIG models (e.g. ProjectMosaicPixel). */ }
		action writeLabels { doc /* PigLabelModel writes geometry labels on each output product. */ }

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
