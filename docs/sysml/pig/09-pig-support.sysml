/*
 * Support classes declared in vos/mars/inc outside the PIG core: Mars 2020 raw
 * telemetry (EDR / PDS label / VICAR label) helpers, point-cloud filter shapes,
 * instrument-placement parameters, legacy M98 radiometry, nav-file XML records
 * and small utilities. Modelled at class level: name, base class, header and
 * the PIG classes or VISOR programs that use them.
 * Not modelled as parts: LogFile and M2020PixlDpMetaData (forward declarations
 * only, no definition in the tree) and PigQuaternion (an attribute def in PigData).
 */
package PigSupport {
	private import ScalarValues::*;
	private import PigData::Files::*;
	private import PigData::Geometry::*;
	private import PigCore::*;

	package M2020Data {
		doc /* Mars 2020 raw data product classes (inc/M2020*.h): telemetry data-product
		 * metadata, EDR decoding per instrument and the PDS / VICAR labels written for them. */
		part def M2020Env { doc /* Run environment: reads the M2020UPF user parameter file. */ part upf : M2020UPF; }
		part def M2020UPF { doc /* Key/value user parameter file (delimiter and comment characters). */ }
		part def M2020Db { doc /* Database connection used to look up product metadata. */ }
		part def M2020Logger { doc /* Log stream (an ofstream). */ }
		part def M2020Tracer { doc /* Traces method entry and exit with timestamps. */ }
		part def M2020Exception { doc /* Exception type thrown by the M2020 helpers (std::exception). */ }
		part def M2020MiscUtil { doc /* Static string helpers (trim, ltrim, ...). */ }

		part def M2020DpMetaData { doc /* Data-product metadata extracted from an .emd file. */ }
		part def M2020DPOMetaData { doc /* Data-product-object metadata extracted from an .emd file. */ }
		part def M2020MMMDpMetaData { doc /* Data-product metadata for MMM (Mastcam-Z, MEDA, MOXIE...) products. */ }
		part def M2020DPOParser { doc /* Extracts DPOs from a data file using a tab-delimited DPO description. */ }
		part def M2020InstrumentHeader { doc /* Base of instrument-specific product headers. */ }
		part def M2020IdphHeader :> M2020InstrumentHeader { doc /* Image data product header. */ }

		part def M2020EdrFactory {
			doc /* createEdr(M2020DpMetaData): the EDR subclass for a product's instrument. */
			ref part creates : M2020Edr[0..*];
			ref part reads : M2020DpMetaData;
		}
		abstract part def M2020Edr {
			doc /* Experiment data record decoded from telemetry DPOs; writes its label. */
			ref part dpMetaData : M2020DpMetaData;
			ref part label : M2020VicarLabel[0..1];
		}
		part def M2020ImgEdr :> M2020Edr { doc /* Image EDR. */ }
		part def M2020EngCamEdr :> M2020ImgEdr { doc /* Engineering-camera image EDR (NavCam, HazCam, CacheCam...). */ }
		part def M2020EDLCamEdr :> M2020EngCamEdr { doc /* EDL camera EDR. */ }
		part def M2020MMMCamEdr :> M2020EngCamEdr { doc /* Mastcam-Z / MMM camera EDR. */ }
		part def M2020SrlcEdr :> M2020EngCamEdr { doc /* Sampling and caching (SRLC) camera EDR. */ }
		part def M2020SuperCamEdr :> M2020EngCamEdr { doc /* SuperCam RMI EDR. */ }
		part def M2020MedaEdr :> M2020Edr { doc /* MEDA EDR. */ }
		part def M2020MoxieEdr :> M2020Edr { doc /* MOXIE EDR. */ }
		part def M2020PixlEdr :> M2020Edr { doc /* PIXL EDR. */ }
		part def M2020RimfaxEdr :> M2020Edr { doc /* RIMFAX EDR. */ }

		part def M2020Label {
			doc /* Base of the product labels: data-product metadata plus instrument header. */
			ref part dpMetaData : M2020DpMetaData;
			ref part header : M2020InstrumentHeader;
		}
		part def M2020VicarLabel :> M2020Label { doc /* VICAR label written on an EDR image. */ }
		part def M2020EngCamVicarLabel :> M2020VicarLabel;
		part def M2020EDLCamVicarLabel :> M2020EngCamVicarLabel;
		part def M2020MMMCamVicarLabel :> M2020EngCamVicarLabel;
		part def M2020SkyCamVicarLabel :> M2020EngCamVicarLabel;
		part def M2020SuperCamVicarLabel :> M2020EngCamVicarLabel;
		part def M2020PixlVicarLabel :> M2020Label;

		part def M2020EngImgPdsLabel { doc /* PDS label of an engineering-camera image. */ }
		part def M2020EngCamPds :> M2020EngImgPdsLabel;
		part def M2020EDLPdsLabel { doc /* PDS label of an EDL product. */ }
		part def M2020EDLPds :> M2020EDLPdsLabel;
		part def M2020MMMImgPdsLabel { doc /* PDS label of an MMM image. */ }
		part def M2020MMMPds :> M2020MMMImgPdsLabel;
		part def M2020SrlcPdsLabel { doc /* PDS label of an SRLC image. */ }
		part def M2020SrlcPds :> M2020SrlcPdsLabel;
		part def M2020SuperCamImgPdsLabel { doc /* PDS label of a SuperCam image. */ }
		part def M2020SuperCamPds :> M2020SuperCamImgPdsLabel;
		part def M2020MedaPds { doc /* PDS label of a MEDA product. */ }
		part def M2020MoxiePds { doc /* PDS label of a MOXIE product. */ }
		part def M2020PixlPds { doc /* PDS label of a PIXL product. */ }
		part def M2020RimfaxPds { doc /* PDS label of a RIMFAX product. */ }
	}

	package PointFilters {
		doc /* inc/FilterShapes.h: shapes that mask image pixels or 3-D points; read from rover-mask
		 * XML (marsautotie MASK) and used by marsfilter and mars_filter_subs. */
		attribute def Point2D { attribute x : Real; attribute y : Real; }
		attribute def Point3D { attribute x : Real; attribute y : Real; attribute z : Real; }
		abstract part def FilterShape {
			doc /* readFromXML() parses one shape element; tests a pixel or point for exclusion. */
			ref item source : RoverMaskFile;
			part rotate : FilterRotate;
		}
		part def FilterShapeImagePolygon :> FilterShape { doc /* Convex polygon in image space. */ attribute vertices : Point2D[3..*] ordered; }
		part def FilterShapeProjectedPolygon :> FilterShape { doc /* 3-D polygon projected into the image through the camera model. */
			attribute vertices : Point3D[3..*] ordered; ref part camera : PigCameraModel; }
		part def FilterShapeProjectedHorizon :> FilterShape { doc /* Mask everything above an elevation (degrees). */ attribute maxElevation : Real; }
		part def FilterShapeVolumeBox :> FilterShape { doc /* Axis-aligned 3-D box. */ attribute min : Point3D; attribute max : Point3D; }
		part def FilterShapeVolumeZCylinder :> FilterShape { doc /* Cylinder along Z. */ attribute axis : Point2D; attribute radius : Real; }
		part def FilterShapeVolumeYWasher :> FilterShape { doc /* Cylinder along Y minus an inner cylinder. */ }
		part def FilterRotate { doc /* Rotation applied to the shapes' frame before testing. */ attribute rotation : PigQuaternion; }
	}

	package InstrumentPlacement {
		doc /* inc/marsi_*.h: instrument footprints (SampleCircle shapes) for the placement programs
		 * marsitilt, marsirough and marsifoot. */
		attribute def SampleCircle { attribute x : Real; attribute y : Real; attribute radius : Real; attribute maxHeight : Real; }
		abstract part def PigInstrumentParams {
			doc /* Body and feet shapes of an instrument (INSTRUMENT parameter). */
			attribute body : SampleCircle[0..*];
			attribute feet : SampleCircle[0..*];
		}
		part def PigNsytSeis_InstrumentParams :> PigInstrumentParams { doc /* InSight SEIS. */ }
		part def PigNsytHP3_InstrumentParams :> PigInstrumentParams { doc /* InSight HP3. */ }
		part def PigNsytWTS_InstrumentParams :> PigInstrumentParams { doc /* InSight wind and thermal shield. */ }
		part def PigM20Heli_InstrumentParams :> PigInstrumentParams { doc /* Ingenuity helicopter drop site. */ }
	}

	package LegacyRadiometry {
		doc /* Radiometry classes outside the mission adapters (sub/mars_radiometry). */
		part def RadiometryCalImage { doc /* Cache of one calibration image (flat, dark...) per instrument. */ ref item image : FlatFieldFile; }
		part def RadiometryCalImageDark :> RadiometryCalImage { doc /* Dark-current calibration image. */ }
		part def RadiometryM98RAC :> RadiometryModel { doc /* Mars Polar Lander robotic-arm camera: flat field by focus and temperature. */ }
		part def RadiometryM98SSI :> RadiometryModel { doc /* Mars Polar Lander surface stereo imager. */ }
	}

	package NavXml {
		doc /* Records of the pointing-correction (nav) XML and the Xerces-C++ wrapper that reads it. */
		part def PigXerces { doc /* Static: initializes and terminates Xerces-C++ once (reference counted); DOM helpers. */ }
		part def PigPCCameraModel {
			doc /* One camera model from a nav file: type, ids, names, values, reference frame (read by PigPointingCorrections). */
			ref item source : NavFile;
		}
		part def PigPointingParams {
			doc /* One set of named pointing parameters from a nav file (type, unique id); read by PigPointingCorrections, mars_apply_navtable. */
			ref item source : NavFile;
		}
	}

	package Utilities {
		part def MeshMan {
			doc /* Loads a single-shape triangular OBJ and intersects rays with it (Embree); used by marsecorr. */
			ref item mesh : MeshFile;
		}
		part def PigCoordM20rmech :> PigCoordSystem {
			doc /* M20 Rover Mechanical frame: Rover Nav shifted along X. Its C++ base PigCoordM20rover.h
			 * is included but not present in this source tree, so it specializes PigCoordSystem here. */
			attribute rmechToRnav : PigPoint;
		}
		part def BasicFile { doc /* Plain fstream wrapper for log and query files. */ }
		part def BasicCcsdsPkt { doc /* CCSDS telemetry packet base (CCSDS 102.0-B-4); subclasses define the secondary header. */ }
	}
}
