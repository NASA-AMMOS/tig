/*
 * Run-time object graph of a multi-input VISOR program after mars_setup():
 * which PIG instances exist, who owns them, and how they reference each other.
 * Multiplicity [*] = one per input image.
 */
package PigRuntime {
	private import PigData::Files::*;
	private import PigData::Calibration::*;
	private import PigCore::*;
	private import PigBehavior::*;
	private import VicarContext::*;

	part def VisorProgram {
		doc /* A mars* program: owns the arrays mars_setup fills (files[], cameras[], pointings[],
		 * radiometric[], brt_corr_models[], surface_model, def_cs). */
		perform action setup : MarsSetup;
	}

	connection def Uses { end client; end supplier; }

	part def MarsProgramRun {
		doc /* Instances and references inside one VISOR process (e.g. marsmap) after setup. */
		part program : VisorProgram;
		part mission : PigMission;
		part rsm : PigRoverStateManager;
		part mapper : PigCameraMapper;
		part pointingCorrections : PigPointingCorrections[0..1];
		part files : PigFileModel[1..*];
		part cameras : PigCameraModel[1..*];
		part pointings : PigPointingModel[1..*];
		part radiometry : RadiometryModel[0..*];
		part brtCorr : PigBrtCorrModel[0..*];
		part frames : PigCoordSystem[1..*];
		part defaultCS : PigCoordSystem;
		part surface : PigSurfaceModel;
		part labelModel : PigLabelModel;
		ref item inputs : VicarImage[1..*];
		ref item calibration : MarsConfigTree;
		ref item navFile : NavFile[0..1];
		ref item rsfFile : RoverStateFile[0..*];
		ref item output : MarsProduct;

		connection programUsesMission : Uses connect program to mission;
		connection missionOwnsRsm : Uses connect mission to rsm;
		connection missionOwnsMapper : Uses connect mission to mapper;
		connection missionCreatesFiles : Uses connect mission to files;
		connection missionCreatesCameras : Uses connect mission to cameras;
		connection missionCreatesPointings : Uses connect mission to pointings;
		connection missionCreatesSurface : Uses connect mission to surface;
		connection fileReadsImage : Uses connect files to inputs;
		connection cameraPointedBy : Uses connect cameras to pointings;
		connection cameraFrames : Uses connect cameras to frames;
		connection pointingFrame : Uses connect pointings to frames;
		connection pointingReadsFile : Uses connect pointings to files;
		connection correctionsApply : Uses connect pointingCorrections to pointings;
		connection correctionsReadNav : Uses connect pointingCorrections to navFile;
		connection rsmDefinesFrames : Uses connect rsm to frames;
		connection rsmReadsRsf : Uses connect rsm to rsfFile;
		connection mapperReadsCalibration : Uses connect mapper to calibration;
		connection radiometryReadsFile : Uses connect radiometry to files;
		connection brtCorrReadsFile : Uses connect brtCorr to files;
		connection surfaceFrame : Uses connect surface to frames;
		connection defaultIsFrame : Uses connect defaultCS to frames;
		connection programUsesSurface : Uses connect program to surface;
		connection programWritesLabels : Uses connect program to labelModel;
		connection labelWritesProduct : Uses connect labelModel to output;
	}

	part marsmapRun : MarsProgramRun {
		doc /* Reference configuration used for traceability: a marsmap mosaic run. */
	}
	part vicar : VicarOpenSource;
}
