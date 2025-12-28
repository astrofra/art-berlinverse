import os
import json

EXCLUDED_DIRS = {"core", "qr"}

def list_all_scn(folder_path):
    all_scn = set()
    for root, dirs, files in os.walk(folder_path, topdown=True):
        # filtre des dossiers exclus
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for f in files:
            if f.endswith(".scn"):
                rel = os.path.relpath(os.path.join(root, f), folder_path).replace("\\", "/")
                all_scn.add(rel)
    return all_scn

def referenced_scn_in_file(scn_file):
    """Retourne l'ensemble des chemins .scn référencés dans la clef 'instances'."""
    refs = set()
    try:
        with open(scn_file, "r", encoding="utf-8") as fp:
            data = json.load(fp)
        for inst in data.get("instances", []):
            name = inst.get("name")
            if isinstance(name, str) and name.endswith(".scn"):
                # normaliser le chemin
                refs.add(name.replace("\\", "/"))
    except Exception as e:
        print(f"[WARN] {scn_file}: {e}")
    return refs

def list_all_referenced_scn(folder_path):
    refs = set()
    for root, dirs, files in os.walk(folder_path, topdown=True):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for f in files:
            if f.endswith(".scn"):
                full = os.path.join(root, f)
                refs |= referenced_scn_in_file(full)
    return refs

def find_unreferenced_scenes(folder_path):
    all_scenes = list_all_scn(folder_path)
    referenced = list_all_referenced_scn(folder_path)
    # garder uniquement celles qui existent vraiment (au cas où une ref cassée traîne)
    referenced = {r for r in referenced if r in all_scenes}
    # scènes non référencées par d'autres scènes
    roots_or_orphans = all_scenes - referenced
    return roots_or_orphans

if __name__ == "__main__":
    root = "../../assets/"
    unreferenced = sorted(find_unreferenced_scenes(root))
    if unreferenced:
        print("Scenes non référencées :")
        for s in unreferenced:
            print("del " + s.replace("/", "\\"))
    else:
        print("Toutes les scènes sont référencées par au moins une autre.")
