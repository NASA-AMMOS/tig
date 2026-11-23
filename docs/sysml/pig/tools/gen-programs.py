#!/usr/bin/env python3
"""Generate 10-mars-programs.sysml from the VISOR program PDFs in a VICAR checkout.

Usage: tools/gen-programs.py <VICAR checkout> > 10-mars-programs.sysml

Every PARM of each program becomes either a typed file item (the FILES table:
direction and item type, read from the PDF help) or a typed attribute of the
program's parameter set. Multiplicities come from COUNT, defaults from DEFAULT
and keyword values from VALID.
"""
import os
import re
import sys

PROGRAMS = [
    "marschkovl", "marsautotie", "marsnav", "marsnav2",
    "marsrad", "marsmap", "marsmos", "marsbrt",
    "marscorr", "marscor3", "marsxyz", "marsrfilt", "marsmesh",
    "marsuvw", "marsslope", "marsrough", "marsitilt", "marsirough", "marsigood", "marsgreach",
]

# Files every program hands to mars_setup; grouped into one <Program>SetupFiles
# item so each program shows its pipeline files, not its setup plumbing.
SETUP = ("CONFIG_PATH", "RSF", "SURF_MESH", "SURF_CSFILE")

# Parameters that name files: (direction, item type). Per-program entries
# override the common ones.
COMMON = {
    "CONFIG_PATH": ("in", "MarsConfigTree"),
    "NAVTABLE": ("in", "NavFile"),
    "RSF": ("in", "RoverStateFile"),
    "BRTCORR": ("in", "BrtCorrFile"),
    "SURF_MESH": ("in", "MeshFile"),
    "SURF_CSFILE": ("in", "CoordSystemFile"),
    "FOOT_COLOR": ("in", "FootprintColorFile"),
    "TIEPOINTS": ("in", "TiepointFile"),
    "BBOX": ("out", "BoundingBoxFile"),
}
FILES = {
    "marschkovl": {"INP": ("in", "InputFileList"), "OUT": ("out", "OverlapList")},
    "marsautotie": {"INP": ("in", "InputFileList"), "OUT": ("out", "TiepointFile"),
                    "MASK": ("in", "RoverMaskFile")},
    "marsnav": {"INP": ("in", "InputFileList"), "OUT": ("out", "NavFile"),
                "IN_TPT": ("in", "TiepointFile"), "OUT_TPT": ("out", "TiepointFile")},
    "marsnav2": {"INP": ("in", "InputFileList"), "OUT": ("out", "NavFile"),
                 "IN_TPT": ("in", "TiepointFile"), "OUT_TPT": ("out", "TiepointFile"),
                 "OUT_BAD": ("out", "TiepointFile")},
    "marsrad": {"INP": ("in", "InputFileList"), "OUT": ("out", "RadiometricImage")},
    "marsmap": {"INP": ("in", "InputFileList"), "OUT": ("out", "MosaicImage"),
                "OVR_OUT": ("out", "OverlapFile"), "IDX_OUT": ("out", "MosaicIndexImage"),
                "ICM_OUT": ("out", "CoregCoordImage")},
    "marsmos": {"INP": ("in", "InputFileList"), "OUT": ("out", "MosaicImage"),
                "IDX_OUT": ("out", "MosaicIndexImage"), "ICM_OUT": ("out", "CoregCoordImage")},
    "marsbrt": {"INP": ("in", "InputFileList"), "OUT": ("out", "BrtCorrFile"),
                "IN_OVR": ("in", "OverlapFile"), "OUT_OVR": ("out", "OverlapFile")},
    "marscorr": {"INP": ("in", "VicarImage"), "OUT": ("out", "DisparityImage"),
                 "MASK": ("out", "CorrelationMaskImage"),
                 "OUT_QUALITY": ("out", "CorrelationQualityImage"),
                 "SEEDFILE": ("in", "TiepointFile")},
    "marscor3": {"INP": ("in", "VicarImage"), "OUT": ("out", "DisparityImage"),
                 "IN_DISP": ("in", "DisparityImage"), "MASK": ("out", "CorrelationMaskImage"),
                 "OUT_QUALITY": ("out", "CorrelationQualityImage"),
                 "IN_COEFS": ("in", "CorrelationCoefsFile"),
                 "OUT_COEFS": ("out", "CorrelationCoefsFile")},
    "marsxyz": {"INP": ("in", "VicarImage"), "OUT": ("out", "XyzImage"),
                "DISPAR": ("in", "DisparityImage"), "ERR_FILE": ("out", "MissDistanceImage")},
    "marsrfilt": {"INP": ("in", "XyzImage"), "OUT": ("out", "XyzImage")},
    "marsmesh": {"INP": ("in", "XyzImage"), "OUT": ("out", "MeshFile"),
                 "IN_SKIN": ("in", "VicarImage")},
    "marsuvw": {"INP": ("in", "XyzImage"), "OUT": ("out", "UvwImage")},
    "marsslope": {"INP": ("in", "XyzImage"), "OUT": ("out", "SlopeImage"),
                  "UVW": ("in", "UvwImage")},
    "marsrough": {"INP": ("in", "XyzImage"), "OUT": ("out", "RoughnessImage"),
                  "UVW": ("in", "UvwImage")},
    "marsitilt": {"INP": ("in", "XyzImage"), "OUT": ("out", "TiltImage"),
                  "UIX_OUT": ("out", "InstrumentNormalImage"),
                  "ZIX_OUT": ("out", "InstrumentZImage"),
                  "UPX_OUT": ("out", "InstrumentPlacementImage"),
                  "XPX_OUT": ("out", "InstrumentPlacementImage")},
    "marsirough": {"INP": ("in", "XyzImage"), "OUT": ("out", "RoughnessImage"),
                   "UIX": ("in", "InstrumentNormalImage"), "ZIX": ("in", "InstrumentZImage")},
    "marsigood": {"INP": ("in", "MarsProduct"), "OUT": ("out", "GoodnessImage"),
                  "MASK": ("in", "VicarImage")},
    "marsgreach": {"INP": ("in", "ReachabilityImage"), "OUT": ("out", "GoodnessImage")},
}

RESERVED = set("""about abstract accept action actor after alias all allocate allocation analysis and
as assert assign assume at attribute bind binding by calc case comment concern connect connection
constant constraint crosses decide def default defined dependency derived do doc else end entry
enum event exhibit exit expose false filter first flow for fork frame from hastype if implies import
in include individual inout interface istype item join language library locale loop merge message
meta metadata new nonunique not null objective occurrence of or ordered out package parallel part
perform port private protected public redefines ref references render rendering rep require
requirement return satisfy send snapshot specializes stakeholder standard state subject subsets
succession terminate then timeslice to transition true until use variant variation verification
verify via view viewpoint when while xor""".split())

TYPES = {"STRING": "String", "REAL": "Real", "INTEGER": "Integer", "INT": "Integer"}


def ident(name):
    n = name.lower()
    return f"'{n}'" if n in RESERVED or not re.fullmatch(r"[a-z_]\w*", n) else n


def camel(name):
    return "".join(w.capitalize() for w in re.split(r"[^A-Za-z0-9]+", name) if w)


def multiplicity(count):
    """TAE COUNT (1, 0:1, (1:20), (0,3), None) -> SysML multiplicity and whether ordered."""
    if count is None:
        return "", False
    c = count.strip("()")
    m = re.fullmatch(r"(\d+)\s*[:,]\s*(\d+)", c)
    lo, hi = (int(m.group(1)), int(m.group(2))) if m else (int(c), int(c))
    text = f"[{lo}]" if lo == hi else f"[{lo}..{hi}]"
    if (lo, hi) == (1, 1):
        text = ""
    return text, hi > 1


def parse_pdf(path):
    text = open(path, errors="replace").read()
    body = re.split(r"(?im)^\s*end-proc", text)[0]
    lines, cur = [], ""
    for line in body.splitlines():
        line = re.sub(r"!.*", "", line).rstrip()
        cur = f"{cur} {line.strip()}" if cur else line.strip()
        if cur.endswith("+"):
            cur = cur[:-1]
            continue
        lines.append(cur)
        cur = ""
    parms = []
    for line in lines:
        m = re.match(r"(?i)PARM\s+(\S+)\s*(.*)", line)
        if not m:
            continue
        name, rest = m.groups()

        def get(key):
            mm = re.search(rf'(?i)\b{key}\s*=\s*(\([^)]*\)|"[^"]*"|[^\s,]+)', rest)
            return mm.group(1) if mm else None

        ptype = (get("TYPE") or "STRING").strip("()").split(",")[0].strip().upper()
        parms.append(dict(name=name.upper(), type=ptype, count=get("COUNT"),
                          default=get("DEFAULT"), valid=get("VALID")))
    helps = {}
    for m in re.finditer(r"(?im)^\.?VARI(?:ABLE)?[ \t]+(\w+)[ \t]*\n(.*?)(?=^\s*\.|^VARI\s)", text, re.S):
        h = re.sub(r"\s+", " ", m.group(2)).strip().replace("*/", "* /")
        helps.setdefault(m.group(1).upper(), h)
    title = ""
    m = re.search(r"(?im)^\.TITLE\s*\n(.*?)(?=^\s*\.)", text, re.S)
    if m:
        title = re.sub(r"\s+", " ", m.group(1)).strip()
    return parms, helps, title


def literal(value, ptype):
    v = value.strip().rstrip(";")
    if v in ("--", ""):
        return None
    if v.startswith("("):
        items = [x.strip() for x in v.strip("()").split(",") if x.strip()]
        vals = [literal(x, ptype) for x in items]
        return None if None in vals else "(" + ", ".join(vals) + ")"
    if ptype in ("REAL", "INTEGER", "INT"):
        if not re.fullmatch(r"[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?", v):
            return None
        if ptype == "REAL":
            if re.fullmatch(r"[-+]?\d+", v):
                v += ".0"
            elif v.endswith("."):
                v += "0"
            elif v.startswith(".") or v.startswith("-.") :
                v = v.replace(".", "0.", 1)
        elif "." in v:
            return None
        return v
    return '"' + v.strip('"').replace('"', "'") + '"'


def short(h, n=150):
    h = h.split(". ")[0].rstrip(".")
    return h if len(h) <= n else h[: n - 3].rstrip() + "..."


def main(root):
    out = []
    w = out.append
    w("/*")
    w(" * Inputs, outputs and parameters of the VISOR programs that the TIG demos run.")
    w(" * GENERATED by tools/gen-programs.py from vos/mars/src/prog/<program>/<program>.pdf;")
    w(" * do not edit by hand. Each program is an action def: file parameters are typed in/out")
    w(" * items (direction from the PDF help), every other PARM is an attribute of <Program>Params.")
    w(" */")
    w("package MarsPrograms {")
    w("\tprivate import ScalarValues::*;")
    w("\tprivate import PigData::Files::*;")
    w("\tprivate import PigData::Products::*;")
    w("\tprivate import PigData::Calibration::*;")
    w("")
    w("\tabstract item def MarsSetupFiles {")
    w("\t\tdoc /* Calibration tree, rover-state and surface files a program passes to mars_setup. */")
    w("\t}")
    for prog in PROGRAMS:
        parms, helps, title = parse_pdf(os.path.join(root, "vos/mars/src/prog", prog, prog + ".pdf"))
        files = dict(COMMON, **FILES[prog])
        enums, attrs, items, setup = [], [], [], []
        for p in parms:
            name, help_ = p["name"], short(helps.get(p["name"], ""))
            mult, ordered = multiplicity(p["count"])
            if p["count"] is None and name == "CONFIG_PATH":
                mult = ""
            if name in files:
                direction, itype = files[name]
                flags = " ordered" if ordered else ""
                if name in SETUP:
                    setup.append(f"\t\tref item {ident(name)} : {itype}{mult}{flags} {{ doc /* {name}: {help_} */ }}")
                    continue
                items.append(f"\t\t{direction} item {ident(name)} : {itype}{mult}{flags} {{ doc /* {name}: {help_} */ }}")
                continue
            if p["type"] == "KEYWORD":
                vals = re.findall(r'"([^"]+)"|([A-Za-z_]\w*)', p["valid"] or "")
                vals = list(dict.fromkeys(a or b for a, b in vals))
                ename = f"{camel(prog)}{camel(name)}"
                enums.append(f"\tenum def {ename} {{ " + " ".join(f"enum '{v}';" for v in vals) + " }")
                dflt = p["default"] and p["default"].strip('"')
                default = f" default = {ename}::'{dflt}'" if dflt in vals and not ordered else ""
                attrs.append(f"\t\tattribute {ident(name)} : {ename}{mult}{default} {{ doc /* {help_} */ }}")
                continue
            stype = TYPES.get(p["type"], "String")
            dflt = literal(p["default"], p["type"]) if p["default"] else None
            if dflt and dflt.startswith("(") and not ordered:
                dflt = None
            default = f" default = {dflt}" if dflt else ""
            flags = " ordered nonunique" if ordered else ""
            rng = p["valid"] if p["valid"] and p["type"] != "STRING" else None
            note = f" VALID {rng}." if rng else ""
            attrs.append(f"\t\tattribute {ident(name)} : {stype}{mult}{flags}{default} {{ doc /* {help_}{note} */ }}")
        unknown = set(FILES[prog]) - {p["name"] for p in parms}
        if unknown:
            sys.exit(f"{prog}: FILES names missing from the PDF: {sorted(unknown)}")
        params = f"{camel(prog)}Params"
        w("")
        w(f"\t// {prog}: {len(items) + len(setup)} file parameters, {len(attrs)} other parameters")
        out.extend(enums)
        w(f"\tattribute def {params} {{")
        w(f"\t\tdoc /* Non-file parameters of {prog}.pdf. */")
        out.extend(attrs)
        w("\t}")
        if setup:
            w(f"\titem def {camel(prog)}SetupFiles :> MarsSetupFiles {{")
            out.extend(setup)
            w("\t}")
        w(f"\taction def {prog} {{")
        w(f"\t\tdoc /* {title or prog} */")
        out.extend(items)
        if setup:
            w(f"\t\tin item setup : {camel(prog)}SetupFiles;")
        w(f"\t\tin attribute params : {params};")
        w("\t}")
    w("}")
    print("\n".join(out))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
