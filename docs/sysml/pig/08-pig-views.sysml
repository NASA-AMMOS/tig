/*
 * Review views. Render with:  sysml *.sysml -render-all ... (see README.md).
 */
package PigViews {
	private import StandardViewDefinitions::*;
	private import Views::*;

	view <'V01'> packages : GeneralView {
		doc /* Model packages and their imports. */
		filter @SysML::Package;
		expose VicarContext; expose PigData; expose PigCore; expose PigMissions;
		expose PigBehavior; expose PigRuntime; expose PigRequirements;
	}
	view <'V02'> vicarLayers {
		attribute depth = 1;
		doc /* Link-time layering of VICAR, PIG and VISOR (client -> supplier). */
		expose VicarContext::VicarOpenSource;
		render asInterconnectionDiagram;
	}
	view <'V04'> modelBases : GeneralView {
		attribute depth = 1;
		doc /* PigModelBase / PigAdjustable and the model families that specialize them. */
		expose PigCore::PigModelBase; expose PigCore::PigAdjustable; expose PigCore::PigMission;
		expose PigCore::PigFileModel; expose PigCore::PigLabelModel; expose PigCore::PigCameraModel;
		expose PigCore::PigPointingModel; expose PigCore::PigCoordSystem; expose PigCore::PigSurfaceModel;
		expose PigCore::RadiometryModel; expose PigCore::PigBrtCorrModel; expose PigCore::PigColorModel;
		expose PigCore::PigSolutionManager; expose PigCore::PigCameraMapper;
	}
	view <'V05'> cameraAndPointing : GeneralView {
		attribute depth = 1;
		filter @SysML::Definition;
		doc /* Camera model types, pointing model families and the camera/pointing/CS associations. */
		expose PigCore::PigCameraModel; expose PigCore::PigCAHV; expose PigCore::PigCAHVOR;
		expose PigCore::PigCAHVORE; expose PigCore::PigPSPH; expose PigCore::PigPointingModel;
		expose PigCore::PigPointBodyFixedCamera; expose PigCore::PigPointPanTiltCamera;
		expose PigCore::PigPointTwoPivotCamera; expose PigCore::PigPointCamera7dof;
		expose PigCore::PigPointCamera6dof; expose PigCore::PigCoordSystem;
		expose PigCore::PigCameraMapper; expose PigCore::PigCameraMapEntry;
	}
	view <'V06'> coordinateSystems : GeneralView {
		attribute depth = 1;
		filter @SysML::Definition;
		doc /* Frame identity, definition, live frames and the solution managers that supply them. */
		expose PigCore::PigCSReference; expose PigCore::PigCSDefinition; expose PigCore::PigCoordSystem;
		expose PigCore::PigSolutionItem; expose PigCore::PigSolutionManager; expose PigCore::PigRoverStateManager;
		expose PigCore::PigPointingCorrections; expose PigCore::PigPCItem; expose PigCore::PigSurfaceModelParams;
		expose PigCore::PigMission;
	}
	view <'V07'> surfacesAndRadiometry : GeneralView {
		attribute depth = 1;
		filter @SysML::Definition;
		doc /* Surface model types and the radiometric / brightness / colour chain. */
		expose PigCore::PigSurfaceModel; expose PigCore::PigSurfacePlane; expose PigCore::PigSurfaceSphere;
		expose PigCore::PigSurfaceSphere2; expose PigCore::PigSurfaceSphere1; expose PigCore::PigSurfaceInfinity;
		expose PigCore::PigSurfaceMesh; expose PigCore::RadiometryModel; expose PigCore::PigBrtCorrModel;
		expose PigCore::PigBrtCorrLinear; expose PigCore::PigBrtCorrHsiLin; expose PigCore::PigColorModel;
		expose PigCore::PigColorConverter;
	}
	view <'V08'> missionFactories : GeneralView {
		attribute depth = 1;
		filter @SysML::Definition;
		doc /* PigMission and the mission adapters. */
		expose PigCore::PigMission; expose PigMissions::MissionFactory;
		expose PigMissions::M20::PigM20; expose PigMissions::MSL::PigMSL; expose PigMissions::MER::PigMER;
		expose PigMissions::NSYT::PigNSYT; expose PigMissions::PHX::PigPHX; expose PigMissions::Legacy::PigMPF;
		expose PigMissions::Legacy::PigFIDO; expose PigMissions::Legacy::PigM01; expose PigMissions::Legacy::PigColdarm;
		expose PigMissions::Legacy::PigPsyche; expose PigMissions::Legacy::PigGenericImage;
	}
	view <'V09'> m20Adapter : GeneralView {
		attribute depth = 1;
		filter @SysML::Definition;
		doc /* Everything the Mars 2020 adapter contributes. */
		expose PigMissions::M20::*;
	}
	view <'V10'> runtimeObjects {
		attribute depth = 1;
		doc /* PIG objects inside one VISOR process after mars_setup. */
		expose PigRuntime::MarsProgramRun;
		render asInterconnectionDiagram;
	}
	view <'V11'> tigInvocation : ActionFlowView {
		doc /* From `tig marsmap ...` on the host to PIG in the container. */
		expose PigBehavior::RunVisorProgramInTig;
	}
	view <'V12'> marsSetupFlow : ActionFlowView { expose PigBehavior::MarsSetup; }
	view <'V13'> readInputsFlow : ActionFlowView { expose PigBehavior::ReadInputModels; }
	view <'V14'> createCameraFlow : ActionFlowView { expose PigBehavior::CreateCameraModel; }
	view <'V15'> resolveCsFlow : ActionFlowView { expose PigBehavior::ResolveCoordSystem; }
	view <'V16'> mosaicPixelFlow : ActionFlowView { expose PigBehavior::ProjectMosaicPixel; }
	view <'V17'> cameraLifecycle : StateTransitionView { expose PigBehavior::CameraModelLifecycle; }
	view <'V18'> requirements : GeneralView {
		doc /* Requirements, what satisfies them and which demo verifies them. */
		filter @SysML::RequirementUsage or @SysML::RequirementDefinition or @SysML::VerificationCaseDefinition or @SysML::SatisfyRequirementUsage;
		expose PigRequirements::**;
	}
}
