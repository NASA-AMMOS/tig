/*
 * Requirements PIG meets today, recovered from its source and comments (not
 * from a project requirements document), with satisfying elements and the TIG
 * demo scripts that exercise them.
 */
package PigRequirements {
	private import PigCore::*;
	private import PigBehavior::*;
	private import PigRuntime::*;
	private import VicarContext::*;

	requirement def PigRequirement { doc /* A capability or constraint of the PIG library. */ }

	requirement <'PIG-01'> multimission : PigRequirement {
		doc /* PIG shall select the mission-specific model implementations from the input image label, without the calling program naming the mission. */
	}
	requirement <'PIG-02'> cameraProjection : PigRequirement {
		doc /* PIG shall project image line/sample to a 3-D ray and a 3-D point to line/sample for CAHV, CAHVOR, CAHVORE and PSPH camera models. */
	}
	requirement <'PIG-03'> cameraSource : PigRequirement {
		doc /* PIG shall build a camera model from the image label or, when the label has none or POINT_METHOD requests it, from mission calibration located through CONFIG_PATH ($MARS_CONFIG_PATH). */
	}
	requirement <'PIG-04'> pointing : PigRequirement {
		doc /* PIG shall point each camera model from the articulation state recorded in its label, with POINT_METHOD overrides. */
	}
	requirement <'PIG-05'> frames : PigRequirement {
		doc /* PIG shall convert points, vectors, az/el and orientations between any two coordinate systems identified by frame name, RMC index set and solution id. */
	}
	requirement <'PIG-06'> roverState : PigRequirement {
		doc /* PIG shall take coordinate-system definitions from RSF/RMC XML files and image labels, choosing between solutions by SOLUTION_ID priority. */
	}
	requirement <'PIG-07'> pointingCorrection : PigRequirement {
		doc /* PIG shall apply pointing corrections (parameters or replacement camera models) from navigation solution files to matching inputs. */
	}
	requirement <'PIG-08'> adjustable : PigRequirement {
		doc /* Pointing models, coordinate systems and surfaces shall expose their parameters and error estimates for adjustment by solvers. */
	}
	requirement <'PIG-09'> surfaces : PigRequirement {
		doc /* PIG shall intersect rays with plane, sphere, infinity and mesh surface models. */
	}
	requirement <'PIG-10'> radiometry : PigRequirement {
		doc /* PIG shall apply mission radiometric correction (flat field, dark, exposure, responsivity) and brightness correction to input DNs. */
	}
	requirement <'PIG-11'> productLabels : PigRequirement {
		doc /* PIG shall write the camera model, coordinate system, surface and product-specific geometry of each derived product into its VICAR label. */
	}
	requirement <'PIG-12'> vicarIo : PigRequirement {
		doc /* PIG shall read and write images, labels and parameters only through VICAR RTL and p2 label routines. */
	}
	requirement <'PIG-13'> embeddable : PigRequirement {
		doc /* Message output and parameter access shall be replaceable functions so PIG can run outside a TAE/VICAR program. */
	}
	requirement <'PIG-14'> setupOrder : PigRequirement {
		doc /* mars_setup shall construct file, camera, pointing, correction, radiometry and surface models in a fixed order shared by all VISOR programs. */
	}

	requirement <'TIG-01'> calibrationProvided {
		doc /* The TIG container shall set MARS_CONFIG_PATH to bundled or mounted calibration so PIG findFile resolves mission calibration. */
	}
	requirement <'TIG-02'> containerInvocation {
		doc /* tig shall run VISOR programs inside the container through vicar-run, translating host paths in arguments and list files. */
	}

	satisfy multimission by marsmapRun.mission;
	satisfy cameraProjection by marsmapRun.cameras;
	satisfy cameraSource by marsmapRun.mapper;
	satisfy pointing by marsmapRun.pointings;
	satisfy frames by marsmapRun.frames;
	satisfy roverState by marsmapRun.rsm;
	satisfy pointingCorrection by marsmapRun.pointingCorrections;
	satisfy adjustable by marsmapRun.pointings;
	satisfy adjustable by marsmapRun.frames;
	satisfy surfaces by marsmapRun.surface;
	satisfy radiometry by marsmapRun.radiometry;
	satisfy radiometry by marsmapRun.brtCorr;
	satisfy productLabels by marsmapRun.labelModel;
	satisfy vicarIo by vicar.pig;
	satisfy embeddable by vicar.pig;
	satisfy setupOrder by marsmapRun.program;
	satisfy calibrationProvided by VicarContext::tig.image;
	satisfy containerInvocation by VicarContext::tig.cli;

	package Verification {
		doc /* TIG demo scripts that run PIG end to end (docs/demos). */
		verification def <'V-PANO'> PanoramaMosaicDemo {
			doc /* demo-panorama-mosaic.sh: marsrad, marsbrt, marsmap (cylindrical/polar/vertical). */
			objective { verify multimission; verify cameraProjection; verify pointing; verify surfaces; verify radiometry; verify productLabels; verify calibrationProvided; verify containerInvocation; }
		}
		verification def <'V-COREG'> CoRegistrationDemo {
			doc /* demo-co-registration.sh: marschkovl, marsautotie, marsnav (, marsnav2). */
			objective { verify adjustable; verify pointingCorrection; verify frames; }
		}
		verification def <'V-MESH'> MeshGenerationDemo {
			doc /* demo-mesh-generation-with-xyz.sh: marscorr/marscor3, marsxyz, marsmesh. */
			objective { verify cameraProjection; verify frames; verify productLabels; }
		}
		verification def <'V-SURF'> SurfaceCharacteristicsDemo {
			doc /* demo-surface-characteristics.sh: marsuvw, marsslope, marsrough, marsitilt, marsigood. */
			objective { verify frames; verify productLabels; verify roverState; }
		}
	}
}
