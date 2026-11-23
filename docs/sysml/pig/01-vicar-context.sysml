/*
 * VICAR / VISOR build context of PIG (Planetary Image Geometry).
 *
 * Layering is taken from VICAR's vos/vicset1_depends.h:
 *   PROD_PIG          -> PROD_VICAR_EXEC (SS_RTL, SS_SHVIC, SS_STAE), SS_P2SUB, EXT_XERCES_CXX
 *   PROD_MARS_SURFACE -> PROD_PIG, SS_MARS, SS_CRUMBS, SS_P1SUB, SS_P2SUB,
 *                        EXT_MPI, EXT_XERCES_CXX, EXT_COIN, EXT_INVENTOR, EXT_CERES, EXT_SIFT
 * so PIG sits on the VICAR core and the VISOR (mars*) programs sit on PIG.
 */
package VicarContext {
	private import ScalarValues::*;

	doc /* The VICAR software system as the environment PIG is built and run in. */

	abstract part def VicarSubsystem {
		doc /* A VICAR subsystem; its doc names the source directory under VICAR's vos/ tree. */
	}

	port def LinkPort {
		doc /* A link-time dependency: the owner calls into the library on the other end. */
	}

	// --- VICAR executive and runtime -----------------------------------
	part def TAE :> VicarSubsystem {
		doc /* Transportable Applications Executive: PDF parameter definitions, TCL procs, menus (vos/tae). */
		port api : ~LinkPort;
	}
	part def STAE :> VicarSubsystem {
		doc /* Subroutine-level TAE interface used by applications to read parameters (vos/stae). */
		port api : ~LinkPort;
		port uses : LinkPort;
	}
	part def ShellVicar :> VicarSubsystem {
		doc /* Shell-VICAR: run VICAR programs from a Unix shell without TAE (vos/shell_vicar). */
		port api : ~LinkPort;
		port uses : LinkPort;
	}
	part def RTL :> VicarSubsystem {
		doc /* VICAR Run-Time Library: zvopen/zvread/zvwrit image I/O, zladd/zlget labels, zvp/zvparmd parameters, zvmessage (vos/rtl). */
		port api : ~LinkPort;
		port uses : LinkPort;
	}

	// --- Subroutine libraries ------------------------------------------
	part def P1Sub :> VicarSubsystem {
		doc /* P1 subroutines (vos/p1). */
		port api : ~LinkPort;
	}
	part def P2Sub :> VicarSubsystem {
		doc /* P2 multimission subroutines (191 libraries) used by PIG: lbl_routines (Lbl*Parms label groups),
		 * cahvor/cmod_* (CAHV/CAHVOR/CAHVORE math), pig_vector (PigVector, PigPoint, PigQuaternion),
		 * mat3, rts_time_routines, return_status, SimpleImage. */
		port api : ~LinkPort;
		port uses : LinkPort;
	}
	part def P2Programs :> VicarSubsystem {
		doc /* 459 general-purpose VICAR application programs (copy, f2, gen, label, ...) (vos/p2/prog). */
		port uses : LinkPort;
	}
	part def P3 :> VicarSubsystem {
		doc /* P3 subroutines and programs (vos/p3). */
		port uses : LinkPort;
	}

	// --- MARS / VISOR subsystem ----------------------------------------
	part def PIGLibrary :> VicarSubsystem {
		doc /* Planetary Image Geometry: the multimission C++ camera, pointing, coordinate-system, surface,
		 * radiometry and label library (vos/mars/src/sub/pig, pig_<mission>, pig_xml; headers vos/mars/inc). */
		port api : ~LinkPort;
		port usesRtl : LinkPort;
		port usesP2 : LinkPort;
		port usesXerces : LinkPort;
		port usesEmbree : LinkPort;
	}
	part def MarsSupport :> VicarSubsystem {
		doc /* mars_support: the mars_setup family that every multi-input mars* program calls to build PIG
		 * models from an INP file list (mars_setup, mars_read_filelist, mars_setup_coords, mars_read_rsf,
		 * mars_apply_navtable, mars_create_pointing_model, mars_read_inputs, mars_footprints, ...). */
		port api : ~LinkPort;
		port usesPig : LinkPort;
		port usesRtl : LinkPort;
	}
	part def MarsSubLibraries :> VicarSubsystem {
		doc /* Other MARS subroutine libraries: mars_radiometry, mars_tiepoints, mars_filter_subs, meshman,
		 * xvector, xyz_to_uvw, marsi_instruments, nsyt_instruments, mica_common and the per-mission
		 * label routines (mer/phx/mpf/mpl/fido_lbl_routines). */
		port api : ~LinkPort;
		port usesPig : LinkPort;
	}
	part def VisorPrograms :> VicarSubsystem {
		doc /* VISOR (VICAR In-Situ Operations for Robotics): 109 mars* application programs (marsmap,
		 * marsnav, marsnav2, marsautotie, marsxyz, marsuvw, marsmesh, marsrad, marsbrt, ...) (vos/mars/src/prog). */
		port usesPig : LinkPort;
		port usesSupport : LinkPort;
		port usesSubs : LinkPort;
		port usesStae : LinkPort;
		port usesP1 : LinkPort;
		port usesShell : LinkPort;
	}
	part def Crumbs :> VicarSubsystem {
		doc /* CRUMBS: mesh/terrain support required by PROD_MARS_SURFACE (vos/crumbs). */
	}
	part def DisplayStack :> VicarSubsystem {
		doc /* Interactive display stack not used by PIG: gui (xvd), vrdi, vids, MotifApp. */
	}

	// --- Third-party externals ------------------------------------------
	part def ExternalLibrary :> VicarSubsystem {
		port api : ~LinkPort;
	}
	part def XercesC :> ExternalLibrary { doc /* EXT_XERCES_CXX: XML DOM parser for nav, RMC/RSF and camera_mapping files (PigXerces). */ }
	part def Embree :> ExternalLibrary { doc /* Intel Embree ray tracer behind PigSurfaceMesh; built only when USES_PIG_MESH (64-bit). */ }
	part def MPI :> ExternalLibrary { doc /* EXT_MPI, used by parallel VISOR programs. */ }
	part def Ceres :> ExternalLibrary { doc /* EXT_CERES bundle adjustment, used by marsnav2. */ }
	part def SIFT :> ExternalLibrary { doc /* EXT_SIFT feature detector, used by marsautotie2. */ }
	part def OpenMP :> ExternalLibrary { doc /* LIB_OMP: threading used by pig_m20 and 24 VISOR programs. */ }

	connection def Links {
		end client : LinkPort;
		end supplier : ~LinkPort;
	}

	// --- The assembled system -------------------------------------------
	part def VicarOpenSource {
		doc /* The VICAR open source release (NASA-AMMOS/VICAR) as linked for VISOR. Each connection is a
		 * link-time dependency from client to supplier. */
		part tae : TAE;
		part stae : STAE;
		part shellVicar : ShellVicar;
		part rtl : RTL;
		part p1 : P1Sub;
		part p2 : P2Sub;
		part p2prog : P2Programs;
		part pig : PIGLibrary;
		part marsSupport : MarsSupport;
		part marsSubs : MarsSubLibraries;
		part visor : VisorPrograms;
		part xerces : XercesC;
		part embree : Embree;

		connection : Links connect visor.usesPig to pig.api;
		connection : Links connect visor.usesSupport to marsSupport.api;
		connection : Links connect visor.usesSubs to marsSubs.api;
		connection : Links connect visor.usesStae to stae.api;
		connection : Links connect visor.usesP1 to p1.api;
		connection : Links connect visor.usesShell to shellVicar.api;
		connection : Links connect shellVicar.uses to rtl.api;
		connection : Links connect marsSupport.usesPig to pig.api;
		connection : Links connect marsSupport.usesRtl to rtl.api;
		connection : Links connect marsSubs.usesPig to pig.api;
		connection : Links connect pig.usesRtl to rtl.api;
		connection : Links connect pig.usesP2 to p2.api;
		connection : Links connect pig.usesXerces to xerces.api;
		connection : Links connect pig.usesEmbree to embree.api;
		connection : Links connect p2.uses to rtl.api;
		connection : Links connect stae.uses to rtl.api;
		connection : Links connect p2prog.uses to p2.api;
		connection : Links connect rtl.uses to tae.api;
	}

	// --- TIG as the deployment of VISOR ---------------------------------
	part def TigContainerImage {
		doc /* terrain-intelligence-generator image: a built VICAR + VISOR tree, vicar-run wrapper, tig-shim
		 * command symlinks and vicario, with mission calibration under MARS_CONFIG_PATH. */
		part vicar : VicarOpenSource;
		attribute marsConfigPath : String = "$MARS_CONFIG_PATH";
	}
	part def TigCli {
		doc /* tig-cli (Python): resolves an unqualified VICAR tool name, translates host paths and runs the tool in a TIG container. */
	}
	part def TigDeployment {
		part cli : TigCli;
		part image : TigContainerImage;
	}
	part tig : TigDeployment;
}
