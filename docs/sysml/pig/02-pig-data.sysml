/*
 * Data types and files PIG reads and writes. Geometry types come from
 * VICAR p2 (pig_vector: PigPoint, PigVector, PigQuaternion).
 */
package PigData {
	private import ScalarValues::*;

	package Geometry {
		attribute def PigVector {
			doc /* 3-vector (x, y, z) with dot/cross/normalize, az/el conversion (p2 PigVector.h). */
			attribute x : Real; attribute y : Real; attribute z : Real;
		}
		attribute def PigPoint :> PigVector { doc /* A location; same representation as PigVector. */ }
		attribute def PigQuaternion {
			doc /* Unit rotation quaternion (s, v) (p2 PigQuaternion.h). */
			attribute s : Real; attribute v : PigVector;
		}
		attribute def ImageCoordinate {
			doc /* VICAR image coordinate: line and sample, 0-based floating point. */
			attribute line : Real; attribute sample : Real;
		}
		attribute def Ray {
			doc /* Projection ray: origin plus unit look direction, expressed in a PigCoordSystem. */
			attribute origin : PigPoint; attribute look : PigVector;
		}
		attribute def AzEl { attribute azimuth : Real; attribute elevation : Real; }
	}

	package Identity {
		attribute def RoverMotionCounter {
			doc /* RMC index set, e.g. (site, drive, pose, arm, ...). Up to PIG_MAX_CS_INDEX values. */
			attribute indices : Integer[0..*] ordered nonunique;
		}
		attribute def CoordSystemIdentity {
			doc /* What names a frame: mission, frame name, RMC index set and solution id,
			 * written as FRAME:(i,j,...);solution. Carried by PigCSReference. */
			attribute mission : String;
			attribute frameName : String;
			attribute rmc : RoverMotionCounter;
			attribute solutionId : String;
			attribute instId : String[0..1];
		}
		attribute def MissionKey {
			doc /* Mission name plus optional host id ("M20:<host>"); selects the PigMission singleton. */
			attribute mission : String; attribute hostId : String[0..1];
		}
	}

	package Files {
		item def VicarImage {
			doc /* A VICAR (or PDS3/PDS4-with-VICAR-label) image opened through RTL zvopen; has a unit number. */
			attribute filename : String;
			attribute unit : Integer;
			attribute nl : Integer; attribute ns : Integer; attribute nb : Integer;
			part label : VicarLabel;
		}
		item def VicarLabel {
			doc /* System, history and property labels. PIG reads/writes property groups through p2
			 * lbl_routines (IDENTIFICATION, GEOMETRIC_CAMERA_MODEL, *_COORDINATE_SYSTEM, ROVER_*,
			 * DERIVED_IMAGE_PARMS, SURFACE_MODEL, RADIOMETRIC_CORRECTION, ...). */
		}
		item def CameraModelFile { doc /* CAHV/CAHVOR/CAHVORE/PSPH calibration model file in the mission calibration tree. */ }
		item def CameraMappingFile { doc /* <mission>_camera_mapping.xml: serial number / instrument id to camera entries (PigCameraMapper). */ }
		item def PointParamsFile { doc /* <mission>.point / pointing-parameter files used by POINT_METHOD and kinematics. */ }
		item def NavFile {
			doc /* Pointing-correction solution XML written by marsnav/marsnav2 and read by
			 * PigPointingCorrections (camera models, pointing parameters, surface model). */
		}
		item def RoverStateFile { doc /* RMC/RSF XML rover-state (coordinate-system) solutions read by PigRoverStateManager. */ }
		item def NavTable { doc /* Legacy navigation table text file applied by mars_apply_navtable. */ }
		item def FlatFieldFile { doc /* Flat-field / dark / responsivity calibration images used by RadiometryModel. */ }
		item def BrtCorrFile { doc /* Brightness-correction XML (marsbrt output) read by PigBrtCorrModel. */ }
		item def MeshFile { doc /* OBJ mesh used as a PigSurfaceMesh surface. */ }
		item def InputFileList {
			doc /* INP parameter: one or more images, or a text list file of images (get_filelist). */
			attribute filenames : String[1..*] ordered;
		}
		item def MarsProduct {
			doc /* A derived image written by a VISOR program with PIG product labels. */
			attribute productType : ProductType;
		}
		enum def ProductType {
			enum mosaicCylindrical; enum mosaicPolar; enum mosaicVertical; enum mosaicSinusoidal;
			enum mosaicCameraModel; enum xyz; enum uvw; enum range; enum disparity; enum slope;
			enum roughness; enum reachability; enum mask; enum radiometric; enum mesh;
		}
	}

	package Calibration {
		item def MarsConfigTree {
			doc /* Calibration directory tree located through the CONFIG_PATH parameter, default
			 * $MARS_CONFIG_PATH (colon-separated); PigModelBase::findFile searches it. */
			ref item cameraModels : Files::CameraModelFile[0..*];
			ref item cameraMapping : Files::CameraMappingFile[0..*];
			ref item pointParams : Files::PointParamsFile[0..*];
			ref item flatFields : Files::FlatFieldFile[0..*];
		}
	}
}
