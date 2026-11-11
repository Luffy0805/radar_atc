#!/usr/bin/env python3
"""Vérifications statiques du mod radar_atc, sans lancer le moteur Luanti.

    python3 tools/check.py [all | syntax globals fields i18n meta tests …] [--missing] [--quiet]

  syntax   compile chaque .lua avec LuaJIT (le moteur Lua de Luanti)
  globals  globales indéfinies (fautes de frappe), globales nouvelles non déclarées
           dans tools/known_globals.txt, globales inutilisées, ordre de chargement
  fields   chaque bouton/champ émis dans ui_tabs.lua est traité dans fields.lua
  i18n     appels S() (arguments @1..@9) et fichiers locale/*.tr (échappements,
           traductions manquantes ou obsolètes)
  meta     mod.conf (version qui recule), réglages documentés, médias, fichiers parasites
  tests    tests unitaires LuaJIT (tools/tests/run.lua)

  --missing  avec i18n : liste les chaînes à traduire, prêtes à coller dans les .tr
  --quiet    n'affiche pas le détail des avertissements

Code de sortie : 0 si aucune erreur (les avertissements ne font pas échouer), 1 sinon.
Prérequis : Python 3.8+ et luajit (macOS : brew install luajit, Debian/Ubuntu : apt install luajit).
"""
import bisect
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODNAME = "radar_atc"
EXPECTED_LANGS = ["fr", "de", "es", "it", "pt", "ru"]
KNOWN_GLOBALS_FILE = ROOT / "tools" / "known_globals.txt"
TEST_RUNNER = ROOT / "tools" / "tests" / "run.lua"

LUA_STD = set("""
_G _VERSION assert collectgarbage dofile error gcinfo getfenv getmetatable ipairs load
loadfile loadstring module newproxy next pairs pcall print rawequal rawget rawset require
select setfenv setmetatable tonumber tostring type unpack xpcall
coroutine debug io math os package string table bit jit
""".split())

LUANTI_API = set("""
minetest core vector ItemStack VoxelArea VoxelManip PseudoRandom PcgRandom SecureRandom
PerlinNoise PerlinNoiseMap ValueNoise ValueNoiseMap Settings AreaStore Raycast
dump dump2 DIR_DELIM INIT PLATFORM LIGHT_MAX
""".split())

# Élément formspec -> position du nom dans ses paramètres séparés par ';'
FIELD_ELEMS = {
    "button": 2, "button_exit": 2, "field": 2, "pwdfield": 2, "textarea": 2,
    "dropdown": 2, "textlist": 2, "table": 2,
    "image_button": 3, "image_button_exit": 3, "item_image_button": 3,
    "checkbox": 1, "tabheader": 1,
}
ELEM_RE = re.compile(
    r"(?<![\w])(" + "|".join(sorted(FIELD_ELEMS, key=len, reverse=True)) + r")\[([^\]]*)")
# Helpers maison qui émettent un élément nommé : fonction -> index (0-based) de l'argument nom
FIELD_HELPERS = {"mkdd": 3}


# ---------------------------------------------------------------------------
#  Rapport
# ---------------------------------------------------------------------------
class Report:
    def __init__(self, quiet=False):
        self.quiet = quiet
        self.errors = 0
        self.warnings = 0
        self._section = []

    def err(self, loc, msg):
        self.errors += 1
        self._section.append(("ERREUR", loc, msg))

    def warn(self, loc, msg):
        self.warnings += 1
        self._section.append(("avert.", loc, msg))

    def section(self, name, fn, *args):
        self._section = []
        try:
            fn(self, *args)
        except Exception as exc:  # un bug de l'outil ne doit pas masquer les autres vérifications
            self.err("tools/check.py", f"la vérification '{name}' a planté : {exc!r}")
        n_err = sum(1 for s in self._section if s[0] == "ERREUR")
        n_warn = len(self._section) - n_err
        status = "OK" if not self._section else f"{n_err} erreur(s), {n_warn} avertissement(s)"
        print(f"== {name} : {status}")
        # Regroupe un même message répété dans un fichier : « fichier:12,15,40 »
        grouped, order = {}, []
        for kind, loc, msg in self._section:
            m = re.match(r"^(.*):(\d+)$", loc)
            fname, line = (m.group(1), m.group(2)) if m else (loc, None)
            key = (kind, fname, msg)
            if key not in grouped:
                grouped[key] = []
                order.append(key)
            if line:
                grouped[key].append(line)
        for kind, fname, msg in order:
            if kind == "avert." and self.quiet:
                continue
            lines = grouped[(kind, fname, msg)]
            loc = f"{fname}:{','.join(lines)}" if lines else fname
            print(f"  {kind:7} {loc}  {msg}")


# ---------------------------------------------------------------------------
#  Lecture du source Lua
# ---------------------------------------------------------------------------
class LuaSource:
    """Découpe un fichier Lua 5.1 en jetons : ('code', texte), ('str', valeur décodée), ('comment', texte)."""

    def __init__(self, path):
        self.path = path
        self.name = str(path.relative_to(ROOT))
        self.text = path.read_text(encoding="utf-8")
        self._nl = [i for i, c in enumerate(self.text) if c == "\n"]
        self.tokens = self._lex()

    def line_of(self, idx):
        return bisect.bisect_right(self._nl, idx - 1) + 1

    def _lex(self):
        src, n = self.text, len(self.text)
        toks, buf, buf_start, i = [], [], 0, 0

        def flush():
            if buf:
                toks.append(("code", "".join(buf), buf_start))
                buf.clear()

        while i < n:
            c = src[i]
            if c == "-" and src.startswith("--", i):
                flush()
                m = re.match(r"\[(=*)\[", src[i + 2:i + 40])
                if m:
                    close = "]" + m.group(1) + "]"
                    k = src.find(close, i + 2 + m.end())
                    k = n if k < 0 else k + len(close)
                else:
                    k = src.find("\n", i)
                    k = n if k < 0 else k
                toks.append(("comment", src[i:k], i))
                i = k
                continue
            if c in "\"'":
                flush()
                start, j, out = i, i + 1, bytearray()
                while j < n and src[j] != c:
                    ch = src[j]
                    if ch == "\\" and j + 1 < n:
                        e = src[j + 1]
                        simple = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b",
                                  "f": "\f", "v": "\v", "\n": "\n"}
                        if e in simple:
                            out += simple[e].encode()
                            j += 2
                        elif e.isdigit():
                            m = re.match(r"\d{1,3}", src[j + 1:j + 4])
                            out.append(int(m.group(0)) & 0xFF)
                            j += 1 + len(m.group(0))
                        else:
                            out += e.encode("utf-8")
                            j += 2
                        continue
                    out += ch.encode("utf-8")
                    j += 1
                toks.append(("str", out.decode("utf-8", errors="replace"), start))
                i = j + 1
                continue
            if c == "[":
                m = re.match(r"\[(=*)\[", src[i:i + 40])
                if m:
                    flush()
                    close = "]" + m.group(1) + "]"
                    k = src.find(close, i + m.end())
                    k = n if k < 0 else k
                    val = src[i + m.end():k]
                    if val.startswith("\n"):
                        val = val[1:]
                    toks.append(("str", val, i))
                    i = k + len(close)
                    continue
            if not buf:
                buf_start = i
            buf.append(c)
            i += 1
        flush()
        return toks


def lua_files():
    return sorted(p for p in ROOT.glob("*.lua"))


_SOURCES = {}


def source(path):
    if path not in _SOURCES:
        _SOURCES[path] = LuaSource(path)
    return _SOURCES[path]


# ---------------------------------------------------------------------------
#  LuaJIT
# ---------------------------------------------------------------------------
LUAJIT = shutil.which("luajit")
_LISTINGS = {}


def luajit_listing(path):
    """Retourne (ok, sortie) de `luajit -bl` (compilation sans exécution)."""
    if path not in _LISTINGS:
        r = subprocess.run([LUAJIT, "-bl", path.name], cwd=path.parent,
                           capture_output=True, text=True)
        _LISTINGS[path] = (r.returncode == 0, r.stdout if r.returncode == 0 else r.stderr)
    return _LISTINGS[path]


def need_luajit(rep):
    if LUAJIT:
        return True
    rep.err("luajit", "introuvable : installez-le (brew install luajit / apt install luajit)")
    return False


# ---------------------------------------------------------------------------
#  syntax
# ---------------------------------------------------------------------------
def check_syntax(rep):
    if not need_luajit(rep):
        return
    for path in lua_files():
        ok, out = luajit_listing(path)
        if not ok:
            msg = out.strip().splitlines()[0] if out.strip() else "erreur inconnue"
            rep.err(path.name, re.sub(r"^luajit:\s*", "", msg))


# ---------------------------------------------------------------------------
#  globals
# ---------------------------------------------------------------------------
HDR_RE = re.compile(r"^-- BYTECODE -- .*:(\d+)-(\d+)\s*$")
INS_RE = re.compile(r"\b(GGET|GSET)\b.*;\s+\"(.*)\"\s*$")


def parse_globals(path):
    """Liste de (op, nom, debut, fin, principal) depuis le listing bytecode."""
    ok, out = luajit_listing(path)
    if not ok:
        return None
    res, start, end, main = [], 0, 0, False
    for line in out.splitlines():
        m = HDR_RE.match(line)
        if m:
            start, end = int(m.group(1)), int(m.group(2))
            main = start == 0
            continue
        m = INS_RE.search(line)
        if m:
            res.append((m.group(1), m.group(2), start, end, main))
    return res


def find_line(path, name, start, end):
    lines = source(path).text.split("\n")
    pat = re.compile(r"(?<![\w.:])" + re.escape(name) + r"(?!\w)")
    lo = max(1, start)
    for ln in range(lo, min(len(lines), max(end, lo)) + 1):
        code = lines[ln - 1].split("--", 1)[0]
        if pat.search(code):
            return ln
    return start or 1


def mod_deps():
    conf = parse_conf(ROOT / "mod.conf")
    deps = set()
    for key in ("depends", "optional_depends"):
        for d in conf.get(key, "").split(","):
            d = d.strip().rstrip("?")
            if d:
                deps.add(d)
    return deps


def load_order():
    init = (ROOT / "init.lua").read_text(encoding="utf-8")
    return re.findall(r'dofile\(.*?"/([\w]+\.lua)"\s*\)', init)


def check_globals(rep):
    if not need_luajit(rep):
        return
    files = lua_files()
    data = {}
    for path in files:
        g = parse_globals(path)
        if g is None:
            rep.err(path.name, "syntaxe invalide, globales non analysées")
            continue
        data[path] = g

    defined = {}   # nom -> fichiers qui l'affectent
    used = set()
    for path, g in data.items():
        for op, name, *_ in g:
            if op == "GSET":
                defined.setdefault(name, set()).add(path.name)
            else:
                used.add(name)
    allowed = LUA_STD | LUANTI_API | mod_deps() | set(defined)

    reported = set()
    for path, g in data.items():
        for op, name, start, end, _ in g:
            if op == "GGET" and name not in allowed and (path, name) not in reported:
                reported.add((path, name))
                ln = find_line(path, name, start, end)
                rep.err(f"{path.name}:{ln}",
                        f"globale '{name}' lue mais jamais définie (faute de frappe ? `local` manquant ailleurs ?)")

    known = set()
    if KNOWN_GLOBALS_FILE.exists():
        for line in KNOWN_GLOBALS_FILE.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                known.add(line)
    else:
        rep.warn("tools/known_globals.txt", "fichier absent : nouvelles globales non contrôlées")
        known = set(defined)

    for name in sorted(set(defined) - known):
        files_ = ", ".join(sorted(defined[name]))
        path = ROOT / sorted(defined[name])[0]
        ln = next((find_line(path, name, s, e) for op, nm, s, e, _ in data.get(path, [])
                   if op == "GSET" and nm == name), 1)
        rep.err(f"{path.name}:{ln}",
                f"nouvelle globale '{name}' ({files_}) : ajouter `local`, ou la déclarer dans tools/known_globals.txt si elle doit être partagée")
    for name in sorted(known - set(defined)):
        rep.warn("tools/known_globals.txt", f"'{name}' n'est plus définie nulle part : retirer la ligne")
    for name in sorted(set(defined) - used):
        rep.warn(", ".join(sorted(defined[name])), f"globale '{name}' définie mais jamais utilisée (code mort ?)")

    # Ordre de chargement : une globale du mod lue au chargement d'un fichier (hors fonctions)
    # doit avoir été définie par un fichier chargé avant lui dans init.lua.
    order = load_order()
    init_defs = {n for op, n, *_ in data.get(ROOT / "init.lua", []) if op == "GSET"}
    avail = set(init_defs)
    for fname in order:
        path = ROOT / fname
        if path not in data:
            if not path.exists():
                rep.err("init.lua", f"dofile() vers {fname}, fichier absent")
            continue
        own = {n for op, n, *_ in data[path] if op == "GSET"}
        for op, name, start, end, main in data[path]:
            if op == "GGET" and main and name in defined and name not in avail | own:
                later = ", ".join(sorted(defined[name]))
                rep.err(f"{fname}:{find_line(path, name, start, end)}",
                        f"'{name}' est lue au chargement mais définie plus tard ({later}) : revoir l'ordre des dofile() dans init.lua")
        avail |= own
    loaded = set(order) | {"init.lua"}
    for path in files:
        if path.name not in loaded:
            rep.warn(path.name, "fichier .lua jamais chargé par init.lua")


# ---------------------------------------------------------------------------
#  fields
# ---------------------------------------------------------------------------
def name_pattern(raw):
    """'btn_sel_%d' -> 'btn_sel_*' ; None si le nom n'est pas statique."""
    raw = raw.strip()
    pat = re.sub(r"%[-+ #0-9.]*[dsi]", "*", raw)
    if not re.fullmatch(r"[A-Za-z_*][\w*]*", pat) or not pat.replace("*", ""):
        return None
    return pat


def emitted_fields():
    out = []  # (motif, fichier, ligne)
    for path in lua_files():
        if path.name == "fields.lua":
            continue
        src = source(path)
        for kind, val, idx in src.tokens:
            if kind != "str":
                continue
            for m in ELEM_RE.finditer(val):
                params = m.group(2).split(";")
                pos = FIELD_ELEMS[m.group(1)]
                if len(params) > pos:
                    pat = name_pattern(params[pos])
                    if pat:
                        out.append((pat, m.group(1), path.name, src.line_of(idx)))
        for helper, argpos in FIELD_HELPERS.items():
            for m in re.finditer(r"(?<![\w.:])" + helper + r"\s*\(", src.text):
                if src.text[max(0, m.start() - 9):m.start()].rstrip().endswith("function"):
                    continue  # définition du helper
                args = split_args(src.text, m.end())
                if len(args) > argpos:
                    lit = re.fullmatch(r"\s*[\"']([\w%]+)[\"']\s*", args[argpos])
                    pat = name_pattern(lit.group(1)) if lit else None
                    if pat:
                        out.append((pat, "dropdown", path.name, src.line_of(m.start())))
    return out


def split_args(text, start):
    """Arguments (texte brut) d'un appel dont la parenthèse ouvrante précède `start`."""
    depth, args, cur, i, quote = 1, [], [], start, None
    while i < len(text) and depth > 0:
        c = text[i]
        if quote:
            cur.append(c)
            if c == "\\":
                cur.append(text[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
            cur.append(c)
        elif c in "([{":
            depth += 1
            cur.append(c)
        elif c in ")]}":
            depth -= 1
            if depth > 0:
                cur.append(c)
        elif c == "," and depth == 1:
            args.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    args.append("".join(cur))
    return args


def handled_fields():
    exact, prefixes = {}, {}  # nom/préfixe -> ligne
    for path in lua_files():
        src = source(path)
        toks = src.tokens
        # variables de boucle liées à une liste littérale : for _, k in ipairs({"a","b"}) do
        loops = []
        for m in re.finditer(r"for\s+[\w\s,]*?\b(\w+)\s+in\s+ipairs\(\s*\{([^}]*)\}\s*\)", src.text):
            vals = re.findall(r"[\"']([^\"']*)[\"']", m.group(2))
            if vals:
                loops.append((m.group(1), vals, src.line_of(m.start())))
        for kind, val, idx in toks:
            if kind == "code":
                for m in re.finditer(r"(?<![\w.:])fields\.([A-Za-z_]\w*)", val):
                    exact.setdefault(m.group(1), (path.name, src.line_of(idx + m.start())))
        for k in range(len(toks) - 2):
            (k1, v1, i1), (k2, v2, i2), (k3, v3, _) = toks[k], toks[k + 1], toks[k + 2]
            # fields[k .. "_suffixe"] avec k lié à une boucle sur une liste littérale
            suf = re.search(r"(?<![\w.:])fields\s*\[\s*([A-Za-z_]\w*)\s*\.\.\s*$", v1) if k1 == "code" else None
            if suf and k2 == "str" and k3 == "code" and re.match(r"\s*\]", v3):
                line = src.line_of(i2)
                for lv, vals, lline in loops:
                    if lv == suf.group(1) and 0 <= line - lline <= 20:
                        for b in vals:
                            exact.setdefault(b + v2, (path.name, line))
                continue
            if k1 == "code" and k2 == "str" and k3 == "code" and re.search(r"(?<![\w.:])fields\s*\[\s*$", v1):
                line = src.line_of(i2)
                if re.match(r"\s*\]", v3):
                    exact.setdefault(v2, (path.name, line))
                    continue
                var = re.match(r"\s*\.\.\s*([A-Za-z_]\w*)\s*\]", v3)
                binding = None
                if var:
                    for lv, vals, lline in loops:
                        if lv == var.group(1) and 0 <= line - lline <= 20:
                            binding = vals
                if binding:
                    for b in binding:
                        exact.setdefault(v2 + b, (path.name, line))
                else:
                    prefixes.setdefault(v2, (path.name, line))
    return exact, prefixes


def check_fields(rep):
    emitted = emitted_fields()
    exact, prefixes = handled_fields()

    def is_handled(pat):
        if "*" not in pat:
            return pat in exact or any(pat.startswith(p) for p in prefixes)
        lit = pat.split("*", 1)[0]
        return lit in prefixes or any(h.startswith(lit) for h in exact)

    seen = set()
    for pat, elem, fname, line in emitted:
        if pat in seen:
            continue
        seen.add(pat)
        if not is_handled(pat):
            what = "bouton" if "button" in elem else elem
            rep.err(f"{fname}:{line}",
                    f"{what} '{pat}' émis mais jamais traité dans fields.lua (clic sans effet / valeur perdue)")

    pats = {p for p, *_ in emitted}
    lits = {p.split("*", 1)[0] for p in pats if "*" in p}
    for name, (fname, line) in sorted(exact.items()):
        if name not in pats and not any(name.startswith(l) for l in lits if l):
            rep.warn(f"{fname}:{line}", f"champ '{name}' lu dans fields.lua mais jamais émis par l'interface")
    for pre, (fname, line) in sorted(prefixes.items()):
        if not any(p.split("*", 1)[0] == pre or p.startswith(pre) for p in pats):
            rep.warn(f"{fname}:{line}", f"préfixe '{pre}…' lu dans fields.lua mais aucun élément correspondant n'est émis")


# ---------------------------------------------------------------------------
#  i18n
# ---------------------------------------------------------------------------
def norm_source_key(s):
    """Clé telle que le client Luanti la cherche dans les .tr (cf. core.translate)."""
    def sub(m):
        c = m.group(1)
        if c in "123456789":
            return "@" + c
        if c == "n":
            return "\n"
        if c == "@":
            return "@@"
        return c
    return re.sub(r"@(.)", sub, s, flags=re.S)


def tr_escape(s):
    return s.replace("\n", "@n").replace("=", "@=")


def source_strings(rep):
    """{clé normalisée: [(fichier, ligne)]} des appels S("...")."""
    keys = {}
    for path in lua_files():
        src = source(path)
        toks = src.tokens
        for k, (kind, val, idx) in enumerate(toks):
            if kind != "code" or not re.search(r"(?<![\w.:])S\s*\(\s*$", val):
                continue
            line = src.line_of(idx + len(val.rstrip()) - 1)
            nxt = toks[k + 1] if k + 1 < len(toks) else None
            if not nxt or nxt[0] != "str":
                rep.warn(f"{path.name}:{line}", "S() appelé sans chaîne littérale : texte non traduisible")
                continue
            after = toks[k + 2][1] if k + 2 < len(toks) and toks[k + 2][0] == "code" else ""
            if re.match(r"\s*\.\.", after):
                rep.warn(f"{path.name}:{line}", "S(\"...\" .. x) : seule une chaîne littérale entière est traduisible")
            # nombre d'arguments après la chaîne
            depth, commas = 1, 0
            for kind2, val2, _ in toks[k + 2:]:
                if kind2 != "code":
                    continue
                for c in val2:
                    if c in "([{":
                        depth += 1
                    elif c in ")]}":
                        depth -= 1
                        if depth == 0:
                            break
                    elif c == "," and depth == 1:
                        commas += 1
                if depth == 0:
                    break
            raw = nxt[1]
            digits = [int(d) for d in re.findall(r"@([1-9])", raw.replace("@@", ""))]
            if digits != list(range(1, len(digits) + 1)):
                rep.err(f"{path.name}:{line}",
                        f"S({raw[:40]!r}…) : les @N doivent apparaître une fois chacun, dans l'ordre @1, @2… (erreur Lua à l'exécution)")
            elif len(digits) != commas:
                rep.err(f"{path.name}:{line}",
                        f"S({raw[:40]!r}…) : {len(digits)} marqueur(s) @N pour {commas} argument(s) (erreur Lua à l'exécution)")
            keys.setdefault(norm_source_key(raw), []).append((path.name, line))
    return keys


def parse_tr(path, rep):
    entries, domain, dups = {}, None, []
    for ln, raw in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        line = raw.rstrip("\r")
        loc = f"{path.relative_to(ROOT)}:{ln}"
        if line.startswith("# textdomain:"):
            domain = line.split(":", 1)[1].strip()
            continue
        if not line.strip() or line.startswith("#"):
            continue
        key, val, i, target = [], [], 0, None
        target = key
        while i < len(line):
            ch = line[i]
            if ch == "@" and i + 1 < len(line):
                nx = line[i + 1]
                target.append("=" if nx == "=" else "\n" if nx == "n" else "@" + nx)
                i += 2
                continue
            if ch == "@":
                rep.warn(loc, "ligne terminée par @ (suite multiligne) : non gérée par l'outil")
            if ch == "=" and target is key:
                target = val
                i += 1
                continue
            target.append(ch)
            i += 1
        if target is key:
            rep.warn(loc, "ligne sans '=' ignorée par Luanti")
            continue
        k, v = "".join(key), "".join(val)
        if k in entries:
            dups.append((ln, entries[k][1], k))
        entries[k] = (v, ln)
    return entries, domain, dups


def check_i18n(rep, show_missing=False):
    src_keys = source_strings(rep)
    locale = ROOT / "locale"
    files = {p.name.split(".")[-2]: p for p in sorted(locale.glob(f"{MODNAME}.*.tr"))}
    for lang in EXPECTED_LANGS:
        if lang not in files:
            rep.err(f"locale/{MODNAME}.{lang}.tr", "fichier de traduction absent")
    for stray in sorted(ROOT.rglob("*.tr")):
        rel = stray.relative_to(ROOT)
        if rel.parts[0] not in ("locale", ".git"):
            rep.warn(str(rel), "fichier .tr hors de locale/ : ignoré par Luanti (copie obsolète ?), à supprimer")

    missing_out = []
    agg = {}  # (gravité, message, ligne) -> langues : un problème commun à plusieurs langues n'est signalé qu'une fois

    def note(kind, lang, line, msg):
        agg.setdefault((kind, msg, line), set()).add(lang)

    for lang, path in files.items():
        entries, domain, dups = parse_tr(path, rep)
        rel = path.relative_to(ROOT)
        if domain != MODNAME:
            note("err", lang, 1, f"en-tête '# textdomain: {MODNAME}' absent ou incorrect")
        for ln, first, key in dups:
            note("warn", lang, ln, f"clé en double (déjà ligne {first}) : {key[:50]!r}")
        covered = set()
        # Source contenant un « = » non échappé : Luanti coupe la clé au premier « = »
        for key, (val, ln) in list(entries.items()):
            if key in src_keys:
                continue
            full = key + "=" + val
            for sk in src_keys:
                if len(sk) > len(key) and full.startswith(sk) and full[len(sk):len(sk) + 1] == "=":
                    covered.add(sk)
                    del entries[key]
                    note("err", lang, ln, f"la source contient « = » : l'écrire @= dans la clé, sinon l'entrée est coupée et jamais utilisée ({sk[:45]!r}…)")
                    break
        for key, (val, ln) in entries.items():
            if "\\n" in key or "\\n" in val or "\\'" in val:
                fixed = key.replace("\\n", "\n").replace("\\'", "'")
                if fixed in src_keys:
                    covered.add(fixed)
                note("err", lang, ln, "échappement invalide : écrire @n (pas \\n) et ' (pas \\') — entrée jamais utilisée en l'état")
                continue
            if not val.strip():
                note("warn", lang, ln, f"traduction vide : {key[:50]!r}")
            ph_k = sorted(set(re.findall(r"@[1-9]", key)))
            ph_v = sorted(set(re.findall(r"@[1-9]", val)))
            if ph_k != ph_v:
                note("err", lang, ln, f"marqueurs différents entre source {ph_k} et traduction {ph_v}")
            if key in src_keys:
                covered.add(key)
            else:
                note("warn", lang, ln, f"clé obsolète (absente du code) : {key[:60]!r}")
        missing = [k for k in src_keys if k not in covered]
        if missing:
            note("warn", lang, None, f"{len(missing)} chaîne(s) non traduite(s) (détail : python3 tools/check.py i18n --missing)")
            missing_out.append((lang, rel, missing))

    # Restitution : une ligne par problème, avec les langues concernées ; erreurs d'abord
    merged = {}
    for (kind, msg, line), langs in agg.items():
        merged.setdefault((kind, msg, tuple(sorted(langs))), []).append(line)
    for (kind, msg, langs), lines in sorted(
            merged.items(), key=lambda kv: (kv[0][0] != "err", min((l or 0) for l in kv[1]))):
        nums = sorted(l for l in lines if l is not None)
        which = langs[0] if len(langs) == 1 else "*"
        loc = f"locale/{MODNAME}.{which}.tr" + (":" + ",".join(map(str, nums)) if nums else "")
        text = msg if len(langs) == 1 else f"{msg} [{', '.join(langs)}]"
        (rep.err if kind == "err" else rep.warn)(loc, text)

    # Modèle de traduction : toutes les chaînes du code, sans traduction
    tpl = locale / "template.txt"
    if not tpl.exists():
        rep.warn("locale/template.txt", "modèle de traduction absent")
    else:
        t_entries, t_domain, _ = parse_tr(tpl, rep)
        if t_domain != MODNAME:
            rep.warn("locale/template.txt", f"en-tête '# textdomain: {MODNAME}' absent")
        absent = sorted(k for k in src_keys if k not in t_entries)
        extra = sorted(k for k in t_entries if k not in src_keys)
        if absent or extra:
            rep.warn("locale/template.txt", f"pas à jour : {len(absent)} chaîne(s) du code absente(s), "
                     f"{len(extra)} chaîne(s) en trop — le régénérer à partir des chaînes du code")

    if show_missing:
        print()
        for lang, rel, missing in missing_out:
            print(f"# {rel} — {len(missing)} chaîne(s) à traduire")
            for k in missing:
                where = ", ".join(f"{f}:{l}" for f, l in src_keys[k][:2])
                print(f"#   ({where})")
                print(f"{tr_escape(k)}=")
            print()


# ---------------------------------------------------------------------------
#  meta
# ---------------------------------------------------------------------------
def parse_conf(path):
    conf = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    return conf


def vkey(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "0"))


def git_versions():
    try:
        shallow = subprocess.run(["git", "rev-parse", "--is-shallow-repository"], cwd=ROOT,
                                 capture_output=True, text=True)
        if shallow.returncode != 0 or shallow.stdout.strip() == "true":
            return None
        log = subprocess.run(["git", "log", "--format=", "-p", "--", "mod.conf"], cwd=ROOT,
                             capture_output=True, text=True)
    except FileNotFoundError:
        return None
    if log.returncode != 0:
        return None
    return re.findall(r"^\+version\s*=\s*(\S+)", log.stdout, flags=re.M)


def check_meta(rep):
    conf = parse_conf(ROOT / "mod.conf")
    if conf.get("name") != MODNAME:
        rep.err("mod.conf", f"name = {conf.get('name')!r}, attendu {MODNAME!r}")
    for k in ("title", "description", "depends", "min_minetest_version", "version", "license"):
        if k not in conf:
            rep.warn("mod.conf", f"clé '{k}' absente")

    cur, hist = conf.get("version"), git_versions()
    if hist is None:
        rep.warn("mod.conf", "historique git indisponible (clone superficiel ?) : contrôle de version ignoré")
    elif cur and hist:
        best = max(hist, key=vkey)
        if vkey(cur) < vkey(best):
            rep.err("mod.conf", f"version {cur} inférieure à {best}, déjà présente dans l'historique git : "
                                "un upload a sans doute écrasé mod.conf")

    # Réglages lus dans config.lua -> documentés ?
    # setting("cle", "défaut") | num("cle", défaut, min, max) | bool("cle", défaut)
    cfg = (ROOT / "config.lua").read_text(encoding="utf-8")
    cfg_defs = {}
    for fn, k, args in re.findall(r"\b(setting|num|bool)\(\s*\"([\w.]+)\"\s*,\s*([^()]*?)\)", cfg):
        vals = [a.strip().strip('"') for a in args.split(",")]
        cfg_defs[k] = (fn, vals)
    keys = list(cfg_defs)
    docs = {"README.md": ROOT / "README.md", "README-FR.txt": ROOT / "README-FR.txt"}
    st = ROOT / "settingtypes.txt"
    for label, path in docs.items():
        if not path.exists():
            rep.warn(label, "fichier absent")
            continue
        text = path.read_text(encoding="utf-8")
        for k in keys:
            if f"{MODNAME}.{k}" not in text:
                rep.warn(label, f"réglage '{MODNAME}.{k}' (config.lua) non documenté")
        for k in sorted(set(re.findall(rf"{MODNAME}\.([a-z_]+)\s*=", text)) - set(keys)):
            rep.warn(label, f"'{MODNAME}.{k}' documenté mais absent de config.lua")
    if not st.exists():
        rep.warn("settingtypes.txt", "absent : les réglages n'apparaissent pas dans le menu Paramètres de Luanti")
    else:
        types = {"int", "float", "bool", "string", "enum", "path", "filepath", "key", "flags", "noise_params", "v3f"}
        expect = {"num": ("int", "float"), "bool": ("bool",), "setting": ("string", "enum")}
        declared = {}
        for ln, line in enumerate(st.read_text(encoding="utf-8").split("\n"), 1):
            if not line.strip() or line.lstrip().startswith(("#", "[")):
                continue
            m = re.match(r"^(\S+)\s+\(([^)]*)\)\s+(\w+)\s*(.*)$", line)
            if not m or m.group(3) not in types:
                rep.err(f"settingtypes.txt:{ln}", "ligne illisible : attendu « nom (Libellé) type défaut [min max] »")
                continue
            name, typ, rest = m.group(1), m.group(3), m.group(4).split()
            if not name.startswith(MODNAME + "."):
                rep.warn(f"settingtypes.txt:{ln}", f"'{name}' sans le préfixe {MODNAME}.")
                continue
            declared[name[len(MODNAME) + 1:]] = (ln, typ, rest)
        for k in keys:
            if k not in declared:
                rep.warn("settingtypes.txt", f"réglage '{MODNAME}.{k}' (config.lua) absent")
                continue
            ln, typ, rest = declared[k]
            fn, vals = cfg_defs[k]
            loc = f"settingtypes.txt:{ln}"
            if typ not in expect[fn]:
                rep.err(loc, f"'{k}' : type {typ}, mais config.lua le lit avec {fn}()")
                continue
            if typ in ("int", "float"):
                st_vals, cfg_vals = rest[:3], vals[:3]
                try:
                    same = len(st_vals) == 3 and [float(v) for v in st_vals] == [float(v) for v in cfg_vals]
                except ValueError:
                    same = False
                if not same:
                    rep.err(loc, f"'{k}' : défaut/min/max {' '.join(st_vals)} ≠ config.lua {' '.join(cfg_vals)}")
            else:
                d = rest[0] if rest else ""
                if d != vals[0]:
                    rep.err(loc, f"'{k}' : défaut {d!r} ≠ config.lua {vals[0]!r}")
        for k in sorted(set(declared) - set(keys)):
            rep.warn(f"settingtypes.txt:{declared[k][0]}", f"'{MODNAME}.{k}' déclaré mais jamais lu par config.lua")
    for wrong in ("settingstype.conf", "settingtypes.conf", "settingstypes.txt"):
        if (ROOT / wrong).exists():
            rep.warn(wrong, "nom incorrect : Luanti ne lit que settingtypes.txt")

    # Médias référencés -> présents ?
    refs = {"textures": set(), "models": set(), "sounds": set()}
    for path in lua_files():
        for kind, val, _ in source(path).tokens:
            if kind != "str":
                continue
            refs["textures"].update(re.findall(r"([\w\-]+\.png)", val))
            refs["models"].update(re.findall(r"([\w\-]+\.(?:obj|b3d|x|gltf|glb))\b", val))
            refs["sounds"].update(re.findall(r"([\w\-]+\.ogg)", val))
    for folder, names in refs.items():
        present = {p.name for p in (ROOT / folder).glob("*")} if (ROOT / folder).exists() else set()
        for n in sorted(names - present):
            if folder == "models":
                rep.err(f"{folder}/{n}", "modèle référencé dans le code mais absent")
            else:
                rep.warn(f"{folder}/{n}", "référencé dans le code mais absent (normal seulement s'il vient d'un autre mod)")
    tex = ROOT / "textures"
    if tex.exists():
        for p in sorted(tex.glob("*.png")):
            if p.name not in refs["textures"]:
                rep.warn(f"textures/{p.name}", "texture jamais référencée dans le code")


# ---------------------------------------------------------------------------
#  tests
# ---------------------------------------------------------------------------
def check_tests(rep):
    if not need_luajit(rep):
        return
    if not TEST_RUNNER.exists():
        rep.warn(str(TEST_RUNNER.relative_to(ROOT)), "absent")
        return
    r = subprocess.run([LUAJIT, str(TEST_RUNNER.relative_to(ROOT))], cwd=ROOT,
                       capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip().splitlines()
    for i, line in enumerate(out):
        detail = out[i + 1].strip() if i + 1 < len(out) and out[i + 1].startswith(" ") else ""
        if line.startswith("ÉCHEC"):
            rep.err("tools/tests", f"{line[5:].strip()} — {detail}")
        elif line.startswith("BUG CONNU"):
            rep.warn("tools/tests", f"bug connu : {line[9:].strip()} — {detail}")
        elif line.startswith("CORRIGÉ"):
            rep.warn("tools/tests", line)
    if r.returncode != 0 and not any(l.startswith("ÉCHEC") for l in out):
        rep.err("tools/tests", "la suite a planté : " + " | ".join(out[-3:]))
    summary = next((l for l in reversed(out) if l.startswith("Résultat")), None)
    if summary:
        print(f"   {summary}")


# ---------------------------------------------------------------------------
CHECKS = {
    "syntax": check_syntax,
    "globals": check_globals,
    "fields": check_fields,
    "i18n": check_i18n,
    "meta": check_meta,
    "tests": check_tests,
}


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = [a for a in argv if not a.startswith("--")]
    flags = {a for a in argv if a.startswith("--")}
    if "--help" in flags or "-h" in argv:
        print(__doc__)
        return 0
    wanted = args or ["all"]
    unknown = [w for w in wanted if w != "all" and w not in CHECKS]
    if unknown:
        print(f"Vérification inconnue : {', '.join(unknown)}. Choix : all, {', '.join(CHECKS)}")
        return 2
    rep = Report(quiet="--quiet" in flags)
    for name, fn in CHECKS.items():
        if "all" in wanted or name in wanted:
            if name == "i18n":
                rep.section(name, fn, "--missing" in flags)
            else:
                rep.section(name, fn)
    print(f"\nRésumé : {rep.errors} erreur(s), {rep.warnings} avertissement(s)")
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
