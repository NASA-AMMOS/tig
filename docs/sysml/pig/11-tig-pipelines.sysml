/*
 * The TIG demo scripts as data-flow pipelines over the VISOR programs of
 * MarsPrograms and a few VICAR core programs. Each step is one `tig <program>`
 * call in the demo; flows connect the file one step writes to the parameter of
 * the step that reads it. Sources: demo-co-registration.sh,
 * demo-panorama-mosaic.sh, demo-mesh-generation-with-xyz.sh,
 * demo-surface-characteristics.sh, demo-change-monitoring.sh.
 */
package TigPipelines {
	private import ScalarValues::*;
	private import PigData::Files::*;
	private import PigData::Products::*;
	private import MarsPrograms::*;

	package VicarTools {
		doc /* VICAR core programs the demos call around the VISOR programs; only the
		 * files the demos pass are modelled (their PDFs are not part of vos/mars). */
		item def PngFile { doc /* 8-bit PNG written by vicario. */ }
		action def f2 { doc /* Pixel arithmetic over one or two images (FUNC). */
			in item inp : VicarImage[1..2] ordered; out item 'out' : VicarImage; in attribute func : String; }
		action def stretch { doc /* Contrast stretch to 8 bits. */
			in item inp : VicarImage; out item 'out' : VicarImage; }
		action def vicario { doc /* VICAR image to PNG. */
			in item inp : VicarImage; out item 'out' : PngFile; }
		action def difpic { doc /* Pixel-by-pixel comparison of two images; reports differences. */
			in item inp : VicarImage[2] ordered; }
		action def copy { doc /* Copy a window (SL, SS, NL, NS) of an image. */
			in item inp : VicarImage; out item 'out' : VicarImage; }
		action def hist { doc /* Histogram and statistics over a window. */
			in item inp : VicarImage; }
		action def label { doc /* List labels (-list). */
			in item inp : VicarImage; }
	}
	private import VicarTools::*;

	action def CoRegistration {
		doc /* demo-co-registration.sh: frames -> overlaps -> tiepoints -> corrected pointing. */
		in item frames : InputFileList;
		out item pointing : NavFile;
		out item tiepoints : TiepointFile;
		attribute runNav2 : Boolean { doc /* --nav2 */ }

		first start;
		action chkovl : marschkovl { doc /* Which frames overlap (OVERLAP threshold). */ }
		action autotie : marsautotie { doc /* Tiepoints between overlapping frames. */ }
		action nav : marsnav { doc /* Pointing solution; -remove drops residual outliers. */ }
		decide nav2Check;
		if runNav2 then nav2;
		else done;
		action nav2 : marsnav2 { doc /* Optional Ceres bundle adjustment for comparison. */ }

		bind chkovl.inp = frames;
		bind autotie.inp = frames;
		bind nav.inp = frames;
		bind nav2.inp = frames;
		flow autotie.'out' to nav.in_tpt;
		flow autotie.'out' to nav2.in_tpt;
		bind pointing = nav.'out';
		bind tiepoints = autotie.'out';

		succession first start then chkovl;
		succession first chkovl then autotie;
		succession first autotie then nav;
		succession first nav then nav2Check;
		succession first nav2 then done;
	}

	action def PanoramaMosaic {
		doc /* demo-panorama-mosaic.sh: radiometric correction, seam brightness matching, mosaic, PNG. */
		in item frames : InputFileList;
		out item panorama : MosaicImage;
		out item png : PngFile;
		attribute brightnessMatch : Boolean { doc /* default; --no-brightness-match skips steps 2-3 */ }

		first start;
		action rad : marsrad { doc /* Step 1, per frame: corrected frames into panorama_frames.txt. */ }
		decide brtCheck;
		if brightnessMatch then overlapMap;
		else mosaic;
		action overlapMap : marsmap { doc /* Step 2: zoom 0.25 mosaic run only to write OVR_OUT overlaps. */ }
		action brt : marsbrt { doc /* Step 3: DO_MULT gain per frame from the overlaps. */ }
		action mosaic : marsmap { doc /* Step 4: the mosaic, with BRTCORR when step 3 ran. */ }
		action str : stretch;
		action toPng : vicario;

		bind rad.inp = frames;
		flow rad.'out' to overlapMap.inp;
		flow rad.'out' to brt.inp;
		flow rad.'out' to mosaic.inp;
		flow overlapMap.ovr_out to brt.in_ovr;
		flow brt.'out' to mosaic.brtcorr;
		flow mosaic.'out' to str.inp;
		flow str.'out' to toPng.inp;
		bind panorama = mosaic.'out';
		bind png = toPng.'out';

		succession first start then rad;
		succession first rad then brtCheck;
		succession first overlapMap then brt;
		succession first brt then mosaic;
		succession first mosaic then str;
		succession first str then toPng;
		succession first toPng then done;
	}

	action def TerrainMesh {
		doc /* demo-mesh-generation-with-xyz.sh (stereo path): disparity, XYZ, filtered XYZ, textured OBJ. */
		in item stereoPair : VicarImage[2] ordered { doc /* left.vic, right.vic */ }
		in item texture : VicarImage { doc /* texture.img: the left frame or --texture */ }
		out item mesh : MeshFile;
		out item pointCloud : XyzImage;

		first start;
		action corr : marscorr { doc /* Initial disparity (disparity_init.img). */ }
		action cor3 : marscor3 { doc /* Refined disparity seeded by IN_DISP. */ }
		action xyz : marsxyz { doc /* Triangulate DISP into pointcloud.xyz. */ }
		action rfilt : marsrfilt { doc /* Range filter of the point cloud. */ }
		action toMesh : marsmesh { doc /* terrain.obj textured with IN_SKIN. */ }

		bind corr.inp = stereoPair;
		bind cor3.inp = stereoPair;
		bind xyz.inp = stereoPair;
		flow corr.'out' to cor3.in_disp;
		flow cor3.'out' to xyz.dispar;
		flow xyz.'out' to rfilt.inp;
		flow rfilt.'out' to toMesh.inp;
		bind toMesh.in_skin = texture;
		bind pointCloud = xyz.'out';
		bind mesh = toMesh.'out';

		succession first start then corr;
		succession first corr then cor3;
		succession first cor3 then xyz;
		succession first xyz then rfilt;
		succession first rfilt then toMesh;
		succession first toMesh then done;
	}

	action def SurfaceCharacteristics {
		doc /* demo-surface-characteristics.sh: normals, slope products, roughness, instrument placement. */
		in item xyz : XyzImage;
		in item reach : ReachabilityImage[0..1] { doc /* --reach */ }
		out item slope : SlopeImage[1..*] { doc /* slope, slope heading, northerly tilt, solar energy */ }
		out item roughness : RoughnessImage;
		out item goodness : GoodnessImage;

		first start;
		action uvwSlope : marsuvw { doc /* -slope normals for the slope family. */ }
		action slopes : marsslope { doc /* One run per SLOPE_TYPE. */ }
		action uvwArm : marsuvw { doc /* Small-patch normals (BOX_RADIUS 5) for roughness. */ }
		action rough : marsrough;
		action itilt : marsitilt { doc /* Tilt for INSTRUMENT, plus UIX_OUT / ZIX_OUT. */ }
		action irough : marsirough { doc /* Instrument roughness from UIX / ZIX. */ }
		action igood : marsigood { doc /* Combine instrument roughness and tilt. */ }
		action greach : marsgreach { doc /* Goodness from the reachability map, when given. */ }

		bind uvwSlope.inp = xyz;
		bind slopes.inp = xyz;
		bind uvwArm.inp = xyz;
		bind rough.inp = xyz;
		bind itilt.inp = xyz;
		bind irough.inp = xyz;
		bind greach.inp = reach;
		flow uvwSlope.'out' to slopes.uvw;
		flow uvwArm.'out' to rough.uvw;
		flow itilt.uix_out to irough.uix;
		flow itilt.zix_out to irough.zix;
		flow irough.'out' to igood.inp;
		flow itilt.'out' to igood.inp;
		bind slope = slopes.'out';
		bind roughness = rough.'out';
		bind goodness = igood.'out';

		succession first start then uvwSlope;
		succession first uvwSlope then slopes;
		succession first slopes then uvwArm;
		succession first uvwArm then rough;
		succession first rough then itilt;
		succession first itilt then irough;
		succession first irough then igood;
		succession first igood then greach;
		succession first greach then done;
	}

	action def ChangeMonitoring {
		doc /* demo-change-monitoring.sh: joint pointing solve over two epochs, identical renders, difference. */
		in item joint : InputFileList { doc /* joint.lis: frames of both epochs */ }
		in item epoch1 : InputFileList;
		in item epoch2 : InputFileList;
		out item difference : VicarImage { doc /* diff_raw / diff_gain / diff_lin / diff_brt */ }
		out item pointing : NavFile;
		attribute useBrtcorr : Boolean { doc /* default; --no-brtcorr skips steps 6-7 */ }

		first start;
		action chkovl : marschkovl;
		action autotie : marsautotie;
		action nav : marsnav { doc /* One solution for both epochs, so both render in the same frame. */ }
		decide brtCheck;
		if useBrtcorr then overlapMap;
		else render1;
		action overlapMap : marsmap { doc /* Joint overlaps (OVR_OUT joint.ovr). */ }
		action brt : marsbrt { doc /* joint.brt from the joint overlaps. */ }
		action render1 : marsmap { doc /* Epoch 1 with the joint NAVTABLE (and BRTCORR). */ }
		action render2 : marsmap { doc /* Epoch 2, same projection and bounds. */ }
		action diff : f2 { doc /* Epoch 2 minus epoch 1, FORMAT REAL. */ }
		action determinism : difpic { doc /* Repeat render of epoch 1 must match exactly. */ }

		bind chkovl.inp = joint;
		bind autotie.inp = joint;
		bind nav.inp = joint;
		bind overlapMap.inp = joint;
		bind brt.inp = joint;
		bind render1.inp = epoch1;
		bind render2.inp = epoch2;
		flow autotie.'out' to nav.in_tpt;
		flow nav.'out' to overlapMap.navtable;
		flow nav.'out' to brt.navtable;
		flow nav.'out' to render1.navtable;
		flow nav.'out' to render2.navtable;
		flow overlapMap.ovr_out to brt.in_ovr;
		flow brt.'out' to render1.brtcorr;
		flow brt.'out' to render2.brtcorr;
		flow render1.'out' to diff.inp;
		flow render2.'out' to diff.inp;
		flow render1.'out' to determinism.inp;
		bind difference = diff.'out';
		bind pointing = nav.'out';

		succession first start then chkovl;
		succession first chkovl then autotie;
		succession first autotie then nav;
		succession first nav then brtCheck;
		succession first overlapMap then brt;
		succession first brt then render1;
		succession first render1 then render2;
		succession first render2 then diff;
		succession first diff then determinism;
		succession first determinism then done;
	}
}
