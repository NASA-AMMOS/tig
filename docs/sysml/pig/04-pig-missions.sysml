/*
 * Mission adapters (vos/mars/src/sub/pig_<mission>). Each PigMission subclass
 * is the factory for its mission's file, label, pointing, radiometry,
 * rover-state and colour models. The "produces*" references record which
 * concrete class each factory method returns.
 */
package PigMissions {
	private import PigCore::*;

	abstract part def MissionFactory :> PigMission {
		doc /* Common shape of a mission adapter: the concrete model classes its factory methods return. */
		ref part producesFileModel : PigFileModel[0..1];
		ref part producesLabelModel : PigLabelModel[0..1];
		ref part producesPointing : PigPointingModel[0..*];
		ref part producesRadiometry : RadiometryModel[0..1];
		ref part producesRoverState : PigRoverStateManager[0..1];
		ref part producesColor : PigColorModel[0..1];
	}

	// ------------------------------------------------------------------
	// Mars 2020 (pig_m20): Perseverance and Ingenuity
	// ------------------------------------------------------------------
	package M20 {
		part def PigFileModelM20 :> PigFileModel;
		part def PigLabelModelM20 :> PigLabelModel;
		part def RadiometryM20 :> RadiometryModel;
		part def PigRoverStateManagerM20 :> PigRoverStateManager;
		part def PigColorModelM20 :> PigColorModel;
		part def PigPointM20mastCamera :> PigPointingModel { doc /* RSM mast (NavCam, Mastcam-Z, SuperCam RMI) kinematics. */ }
		part def PigPointM20mastCamera3dof :> PigPointM20mastCamera;
		part def PigPointM20mastCameraScale :> PigPointM20mastCamera3dof;
		part def PigPointM20armCamera :> PigPointCamera7dof { doc /* Robotic-arm cameras (WATSON, SHERLOC ACI, PIXL MCC). */ }
		part def PigPointM20armCamera6dof :> PigPointCamera6dof;
		part def PigPointM20heliCamera :> PigPointM20armCamera { doc /* Ingenuity helicopter cameras. */ }
		part def PigPointM20heliCamera6dof :> PigPointM20armCamera6dof;
		part def PigPointM20BodyFixedCamera :> PigPointBodyFixedCamera { doc /* Hazcams, EDL and Cachecam. */ }
		part def PigM20 :> MissionFactory {
			doc /* Mars 2020. Camera models from labels or from camera_mapping + calibration interpolated over
			 * filter, focus and temperature; host id separates rover and helicopter. Uses OpenMP. */
			ref part :>> producesFileModel : PigFileModelM20;
			ref part :>> producesLabelModel : PigLabelModelM20;
			ref part :>> producesRadiometry : RadiometryM20;
			ref part :>> producesRoverState : PigRoverStateManagerM20;
			ref part :>> producesColor : PigColorModelM20;
			ref part mast : PigPointM20mastCamera :> producesPointing;
			ref part arm : PigPointM20armCamera :> producesPointing;
			ref part heli : PigPointM20heliCamera :> producesPointing;
			ref part bodyFixed : PigPointM20BodyFixedCamera :> producesPointing;
		}
	}

	// ------------------------------------------------------------------
	// MSL (pig_msl): Curiosity
	// ------------------------------------------------------------------
	package MSL {
		part def PigFileModelMSL :> PigFileModel;
		part def PigLabelModelMSL :> PigLabelModel;
		part def RadiometryMSL :> RadiometryModel;
		part def PigRoverStateManagerMSL :> PigRoverStateManager;
		part def PigPointMSLmastCamera :> PigPointingModel { doc /* RSM mast: NavCam, Mastcam, ChemCam RMI. */ }
		part def PigPointMSLmastCamera3dof :> PigPointMSLmastCamera;
		part def PigPointMSLmastCameraScale :> PigPointMSLmastCamera3dof;
		part def PigPointMSLmahliCamera :> PigPointCamera7dof { doc /* MAHLI on the arm. */ }
		part def PigPointMSLmahliCamera6dof :> PigPointCamera6dof;
		part def PigPointMSLBodyFixedCamera :> PigPointBodyFixedCamera { doc /* Hazcams, MARDI. */ }
		part def PigMSL :> MissionFactory {
			ref part :>> producesFileModel : PigFileModelMSL;
			ref part :>> producesLabelModel : PigLabelModelMSL;
			ref part :>> producesRadiometry : RadiometryMSL;
			ref part :>> producesRoverState : PigRoverStateManagerMSL;
			ref part mast : PigPointMSLmastCamera :> producesPointing;
			ref part mahli : PigPointMSLmahliCamera :> producesPointing;
			ref part bodyFixed : PigPointMSLBodyFixedCamera :> producesPointing;
		}
	}

	// ------------------------------------------------------------------
	// MER (pig_mer): Spirit and Opportunity
	// ------------------------------------------------------------------
	package MER {
		part def PigFileModelMER :> PigFileModel;
		part def PigLabelModelMER :> PigLabelModel;
		part def RadiometryMER :> RadiometryModel;
		part def PigRoverStateManagerMER :> PigRoverStateManager;
		part def PigPointMERpmaCamera :> PigPointPanTiltCamera { doc /* Pancam Mast Assembly: Pancam, NavCam. */ }
		part def PigPointMERpmaCamera3dof :> PigPointMERpmaCamera;
		part def PigPointMERiddCamera :> PigPointingModel { doc /* Microscopic Imager on the IDD arm. */ }
		part def PigPointMERBodyFixedCamera :> PigPointBodyFixedCamera { doc /* Hazcams, DIMES. */ }
		part def PigMER :> MissionFactory {
			ref part :>> producesFileModel : PigFileModelMER;
			ref part :>> producesLabelModel : PigLabelModelMER;
			ref part :>> producesRadiometry : RadiometryMER;
			ref part :>> producesRoverState : PigRoverStateManagerMER;
			ref part pma : PigPointMERpmaCamera :> producesPointing;
			ref part idd : PigPointMERiddCamera :> producesPointing;
			ref part bodyFixed : PigPointMERBodyFixedCamera :> producesPointing;
		}
	}

	// ------------------------------------------------------------------
	// InSight (pig_nsyt)
	// ------------------------------------------------------------------
	package NSYT {
		part def PigFileModelNSYT :> PigFileModel;
		part def PigLabelModelNSYT :> PigLabelModel;
		part def RadiometryNSYT :> RadiometryModel;
		part def PigRoverStateManagerNSYT :> PigRoverStateManager;
		part def PigColorModelNSYT :> PigColorModel;
		part def PigPointNSYTarmCamera :> PigPointCamera7dof { doc /* IDC on the IDA arm. */ }
		part def PigPointNSYTarmCamera6dof :> PigPointCamera6dof;
		part def PigPointNSYTBodyFixedCamera :> PigPointBodyFixedCamera { doc /* ICC lander camera. */ }
		part def PigNSYT :> MissionFactory {
			ref part :>> producesFileModel : PigFileModelNSYT;
			ref part :>> producesLabelModel : PigLabelModelNSYT;
			ref part :>> producesRadiometry : RadiometryNSYT;
			ref part :>> producesRoverState : PigRoverStateManagerNSYT;
			ref part :>> producesColor : PigColorModelNSYT;
			ref part arm : PigPointNSYTarmCamera :> producesPointing;
			ref part bodyFixed : PigPointNSYTBodyFixedCamera :> producesPointing;
		}
	}

	// ------------------------------------------------------------------
	// Phoenix (pig_phx)
	// ------------------------------------------------------------------
	package PHX {
		part def PigFileModelPHX :> PigFileModel;
		part def PigLabelModelPHX :> PigLabelModel;
		part def RadiometryPHX :> RadiometryModel;
		part def PigRoverStateManagerPHX :> PigRoverStateManager;
		part def PigConfigMgrTempPHX :> PigModelBase { doc /* Temperature-dependent camera configuration. */ }
		part def PigPointPHXssiCamera :> PigPointPanTiltCamera { doc /* Surface Stereo Imager. */ }
		part def PigPointPHXssiCamera3dof :> PigPointPHXssiCamera;
		part def PigPointPHXracCamera :> PigPointingModel { doc /* Robotic Arm Camera. */ }
		part def PigPointPHXracCamera6dof :> PigPointPHXracCamera;
		part def PigPHX :> MissionFactory {
			ref part :>> producesFileModel : PigFileModelPHX;
			ref part :>> producesLabelModel : PigLabelModelPHX;
			ref part :>> producesRadiometry : RadiometryPHX;
			ref part :>> producesRoverState : PigRoverStateManagerPHX;
			ref part ssi : PigPointPHXssiCamera :> producesPointing;
			ref part rac : PigPointPHXracCamera :> producesPointing;
		}
	}

	// ------------------------------------------------------------------
	// Smaller and legacy adapters
	// ------------------------------------------------------------------
	package Legacy {
		part def PigFileModelMpf :> PigFileModel;
		part def RadiometryMpfImp :> RadiometryModel;
		part def PigRoverStateManagerMPF :> PigRoverStateManager;
		part def PigPointMpfImp :> PigPointPanTiltCamera { doc /* IMP lander camera. */ }
		part def PigPointMpfRover :> PigPointBodyFixedCamera { doc /* Sojourner rover cameras. */ }
		part def PigMPF :> MissionFactory {
			doc /* Mars Pathfinder. */
			ref part :>> producesFileModel : PigFileModelMpf;
			ref part :>> producesRadiometry : RadiometryMpfImp;
			ref part :>> producesRoverState : PigRoverStateManagerMPF;
			ref part imp : PigPointMpfImp :> producesPointing;
			ref part rover : PigPointMpfRover :> producesPointing;
		}

		part def PigFileModelFIDO :> PigFileModel;
		part def RadiometryFIDO :> RadiometryModel;
		part def PigRoverStateManagerFIDO :> PigRoverStateManager;
		part def PigPointFIDOMastArmCamera :> PigPointingModel;
		part def PigPointFIDOMastArmCamera2DOF :> PigPointFIDOMastArmCamera;
		part def PigPointFIDOBodyFixedCamera :> PigPointBodyFixedCamera;
		part def PigFIDO :> MissionFactory {
			doc /* FIDO terrestrial rover testbed. */
			ref part :>> producesFileModel : PigFileModelFIDO;
			ref part :>> producesRadiometry : RadiometryFIDO;
			ref part :>> producesRoverState : PigRoverStateManagerFIDO;
			ref part mastArm : PigPointFIDOMastArmCamera :> producesPointing;
			ref part bodyFixed : PigPointFIDOBodyFixedCamera :> producesPointing;
		}

		part def PigPointM01Pancam :> PigPointTwoPivotCamera;
		part def PigM01 :> MissionFactory {
			doc /* Mars 2001 (Athena Pancam testbed). */
			ref part pancam : PigPointM01Pancam :> producesPointing;
		}

		part def PigFileModelColdarm :> PigFileModel;
		part def PigLabelModelColdarm :> PigLabelModel;
		part def RadiometryColdarm :> RadiometryModel;
		part def PigRoverStateManagerColdarm :> PigRoverStateManager;
		part def PigColorModelColdarm :> PigColorModel;
		part def PigPointColdarmBodyFixedCamera :> PigPointBodyFixedCamera;
		part def PigColdarm :> MissionFactory {
			doc /* COLDArm (Cold Operable Lunar Deployable Arm) testbed. */
			ref part :>> producesFileModel : PigFileModelColdarm;
			ref part :>> producesLabelModel : PigLabelModelColdarm;
			ref part :>> producesRadiometry : RadiometryColdarm;
			ref part :>> producesRoverState : PigRoverStateManagerColdarm;
			ref part :>> producesColor : PigColorModelColdarm;
			ref part bodyFixed : PigPointColdarmBodyFixedCamera :> producesPointing;
		}

		part def PigFileModelPsyche :> PigFileModel;
		part def PigLabelModelPsyche :> PigLabelModel;
		part def RadiometryPsyche :> RadiometryModel;
		part def PigRoverStateManagerPsyche :> PigRoverStateManager;
		part def PigColorModelPsyche :> PigColorModel;
		part def PigPointPsycheBodyFixedCamera :> PigPointBodyFixedCamera;
		part def PigPsyche :> MissionFactory {
			doc /* Psyche spacecraft imager. */
			ref part :>> producesFileModel : PigFileModelPsyche;
			ref part :>> producesLabelModel : PigLabelModelPsyche;
			ref part :>> producesRadiometry : RadiometryPsyche;
			ref part :>> producesRoverState : PigRoverStateManagerPsyche;
			ref part :>> producesColor : PigColorModelPsyche;
			ref part bodyFixed : PigPointPsycheBodyFixedCamera :> producesPointing;
		}

		part def PigFileModelGeneric :> PigFileModel;
		part def PigRoverStateManagerGeneric :> PigRoverStateManager;
		part def PigPointGenericCamera_0DOF :> PigPointBodyFixedCamera;
		part def PigPointGenericCamera_AzEl :> PigPointPanTiltCamera;
		part def PigPointGenericCamera_6dof :> PigPointCamera6dof;
		part def PigPointGenericCamera_7dof :> PigPointCamera7dof;
		part def PigGenericImage :> MissionFactory {
			doc /* Fallback for images whose label names no supported mission; pointing from POINT_METHOD
			 * parameters (0DOF, AzEl, 6dof, 7dof). */
			ref part :>> producesFileModel : PigFileModelGeneric;
			ref part :>> producesRoverState : PigRoverStateManagerGeneric;
			ref part fixed0 : PigPointGenericCamera_0DOF :> producesPointing;
			ref part azel : PigPointGenericCamera_AzEl :> producesPointing;
			ref part dof6 : PigPointGenericCamera_6dof :> producesPointing;
			ref part dof7 : PigPointGenericCamera_7dof :> producesPointing;
		}
	}
}
