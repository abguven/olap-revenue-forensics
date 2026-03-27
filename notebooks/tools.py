from IPython.display import Markdown, display
import pandas as pd
import numpy as np

import unicodedata
import re

def to_padded_str(val, zero_pad=2, regex_to_remove=r'\.0$'):
    """
    Nettoie un code : enlève une partie avec regex, applique zfill,
    conserve NaN/None.
    - zero_pad : longueur souhaitée après padding
    - regex_to_remove : motif regex à retirer
    """
    if pd.isna(val) or val in ["None","none", "nan", "NaN", ""]:
        return np.nan
    
    return re.sub(regex_to_remove, '', str(val)).zfill(zero_pad)
 

def verify_column_reproducibility(df, target_col, compute_func, return_df=False):
    check_col = target_col + "_check"
    temp_incoherences = None
    temp_df = df.assign(
        **{check_col: compute_func(df)}
    )
    df_compare = temp_df[target_col] == temp_df[check_col]
    n_total = len(df)
    n_errors = (~df_compare).sum()
    error_pct = n_errors / n_total * 100

    if df_compare.all():
        display(Markdown(f"✅ **{target_col}** peut être calculé à 100%"))
    else:
        display(Markdown(
            f"❌ **{target_col}** ne peut PAS être complètement calculé à 100%<br>"
            f"🟠 **{n_errors} erreurs ({error_pct:.1f}%)** sur {n_total} lignes"
        ))
        temp_incoherences = temp_df.loc[~df_compare,]
        if not return_df:
            display(temp_incoherences[[target_col, check_col]].head())        
    
    return temp_incoherences if return_df else None
       
def get_possible_candidates(df, verbose=False):
    candidates = []
    for col in df.columns:
        if df[col].nunique() == df.shape[0]:
            candidates.append(col)
    
    if verbose:
        display(Markdown("#### 🔍 Analyse des colonnes pour trouver des clés candidates"))
        
        if candidates:
            result = f"> **🎯 {len(candidates)} clé candidate(s) trouvée(s) :**\n>\n"
            for candidate in candidates:
                result += f"> - ✅ `{candidate}`\n"
            display(Markdown(result))
        else:
            display(Markdown("> **❌ Aucune clé candidate trouvée**"))
    
    return candidates if candidates else None

def format_french_underscore(x):
    return f"{x:_.2f}".replace('.', ',')

def display_stats(df, columns=None):
    # Gestion du paramètre columns
    if columns is None:
        # Toutes les colonnes
        cols_to_process = df.columns
    elif isinstance(columns, str):
        # Une seule colonne en string
        cols_to_process = [columns]
    elif isinstance(columns, list):
        # Liste de colonnes
        cols_to_process = columns
    else:
        raise ValueError("Le paramètre 'columns' doit être None, str ou list")

    # Vérifier que les colonnes existent
    missing_cols = [col for col in cols_to_process if col not in df.columns]
    if missing_cols:
        raise ValueError(f"Colonnes inexistantes: {missing_cols}")

    for col in cols_to_process:
        display(Markdown("---"))
        display(Markdown(f"**Colonne: {col}**"))

        # Afficher le VRAI type
        print(f"🔍 Type réel: {df[col].dtype}")

        # Pour gérer les types datetime
        if pd.api.types.is_datetime64_any_dtype(df[col]):
            print(f"Période: {df[col].min()} à {df[col].max()}")

        # Pour détecter les "faux float" (entiers stockés en float)
        if df[col].dtype == 'float64':
            if ( (df[col] % 1 == 0) | (df[col].isna()) ).all():
                print("⚠️ Cette colonne pourrait être convertie en int")

        # Mémoire utilisée (utile en data engineering)
        memory_mb = df[col].memory_usage(deep=True) / 1024**2
        print(f"📊 Mémoire: {memory_mb:.2f} MB")

        # Statistiques adaptées selon le type
        if df[col].dtype in ['int64', 'float64']:
            describe_stats = df[[col]].describe()            
            display(describe_stats.style.format(format_french_underscore))
        else:
            # Pour les colonnes Object, afficher des stats pertinentes
            max_len = df[col].dropna().astype(str).str.len().max() # la longueur max du texte SANS tenir compte des NaN
            min_len = df[col].dropna().astype(str).str.len().min() # la longueur min du texte SANS tenir compte des NaN
            print(f"Longueur min du texte: {min_len}")
            print(f"Longueur max du texte: {max_len}")
            print(f"Valeurs uniques: {df[col].nunique()}")
            print(f"Valeurs les plus fréquentes:")
            display(pd.DataFrame(df[col].value_counts()).head())

        # Valeurs manquantes
        missing_count = df[col].isnull().sum()
        missing_percentage = df[col].isnull().mean().round(3)*100
        if missing_count > 0:
            print(f"⚠️ Il y a {missing_count} valeurs manquantes dans la colonne '{col}' soit {missing_percentage}%")
        else:
            print(f"✅ Pas de valeurs manquantes dans la colonne '{col}'")


def save_stats_to_csv(df, output_path="stats.csv", columns=None):
    """
    Sauvegarde les statistiques des colonnes d'un DataFrame dans un fichier CSV.
    
    Args:
        df (pd.DataFrame): Le DataFrame à analyser.
        output_path (str): Chemin du fichier CSV de sortie.
        columns (list|str|None): Colonnes à analyser (None = toutes).
    """
    # Gestion du paramètre columns
    if columns is None:
        cols_to_process = df.columns
    elif isinstance(columns, str):
        cols_to_process = [columns]
    elif isinstance(columns, list):
        cols_to_process = columns
    else:
        raise ValueError("Le paramètre 'columns' doit être None, str ou list")

    # Vérifier que les colonnes existent
    missing_cols = [col for col in cols_to_process if col not in df.columns]
    if missing_cols:
        raise ValueError(f"Colonnes inexistantes: {missing_cols}")

    # Liste pour stocker les stats
    stats_list = []

    for col in cols_to_process:
        col_stats = {"colonne": col, "dtype": str(df[col].dtype)}

        # Type datetime
        if pd.api.types.is_datetime64_any_dtype(df[col]):
            col_stats["min"] = df[col].min()
            col_stats["max"] = df[col].max()

        # Faux float = entiers déguisés
        if df[col].dtype == 'float64':
            if ((df[col] % 1 == 0) | (df[col].isna())).all():
                col_stats["note"] = "⚠️ Colonne convertible en int"

        # Mémoire utilisée
        col_stats["memoire_MB"] = round(df[col].memory_usage(deep=True) / 1024**2, 3)

        # Statistiques numériques
        if df[col].dtype in ['int64', 'float64']:
            desc = df[col].describe()
            for stat_name, stat_value in desc.items():
                col_stats[stat_name] = stat_value
        else:
            # Colonnes catégoriques/objets
            col_stats["longueur_max"] = df[col].dropna().astype(str).str.len().max()
            col_stats["valeurs_uniques"] = df[col].nunique()
            top_values = df[col].value_counts().head(3).to_dict()
            col_stats["top_values"] = str(top_values)

        # Valeurs manquantes
        missing_count = df[col].isnull().sum()
        missing_percentage = df[col].isnull().mean() * 100
        col_stats["nb_nan"] = missing_count
        col_stats["pct_nan"] = round(missing_percentage, 2)

        stats_list.append(col_stats)

    # Conversion en DataFrame
    stats_df = pd.DataFrame(stats_list)

    # Sauvegarde en CSV
    stats_df.to_csv(output_path, index=False, encoding="utf-8-sig")
    print(f"✅ Statistiques sauvegardées dans {output_path}")


def report_shape_changes(shape_before, shape_after):
    """
    Affiche un rapport sur les changements de dimensions (lignes/colonnes) entre deux formes.
    
    Args:
        shape_before (tuple): Forme initiale du DataFrame (ex: df.shape).
        shape_after (tuple): Forme finale du DataFrame.
    """
    
    print(f"Shape avant: {shape_before}")
    print(f"Shape après: {shape_after}")
    
    rows_diff = shape_before[0] - shape_after[0]
    cols_diff = shape_before[1] - shape_after[1]

    # Messages pour les lignes
    if rows_diff > 0:
        print(f"  ✂️  Lignes supprimées: {rows_diff}")
    elif rows_diff < 0:
        print(f"  ➕ Lignes ajoutées: {abs(rows_diff)}")
    
    
    if cols_diff > 0:
        print(f"  🗑️  Colonnes supprimées: {cols_diff}")
    elif cols_diff < 0:
        print(f"  📊 Colonnes ajoutées: {abs(cols_diff)}")
    
    if rows_diff == 0 and cols_diff == 0:
        print(f"  🔄 Aucun changement de dimension")

def normalize_commune(commune_name):
    """
    Normalise un nom de commune de manière robuste.
    1. Corrige les corruptions d'encodage spécifiques.
    2. Tente une réparation d'encodage générique.
    3. Supprime les articles définis en début de nom (Le, La, Les, L').
    4. Supprime les accents, gère les ligatures et standardise le format.
    """
    if pd.isna(commune_name):
        return ""

    text = str(commune_name).strip()

    # ÉTAPE 1 : CORRECTIONS MANUELLES POUR LES CAS SPÉCIFIQUES
    if "SchÄ°lcher" in text:
        text = text.replace("SchÄ°lcher", "Schoelcher")
    if "SchÅ“lcher" in text:
        text = text.replace("SchÅ“lcher", "Schoelcher")

    # ÉTAPE 2 : TENTATIVE DE RÉPARATION D'ENCODAGE GÉNÉRIQUE
    try:
        text = text.encode('latin1').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass

    # ÉTAPE 3 : SUPPRESSION DES ARTICLES EN DÉBUT DE NOM (NOUVELLE ÉTAPE !)
    # Regex pour trouver "le ", "la ", "les ", "l'" au début, insensible à la casse
    pattern = r"^(le\s+|la\s+|les\s+|l')"
    text = re.sub(pattern, "", text, flags=re.IGNORECASE).strip()

    # ÉTAPE 4 : NORMALISATION STANDARD
    text = text.replace('œ', 'oe').replace('Œ', 'OE')
    nfkd_form = unicodedata.normalize('NFD', text)
    text = "".join([c for c in nfkd_form if not unicodedata.combining(c)])
    text = re.sub(r'[\s-]+', ' ', text) # Remplace tirets et espaces multiples par un seul espace
    
    return text.upper().strip()

def print_md(txt):
    display(Markdown(txt))


def get_duplicates_in_subset(df, columns_to_check = None, sort_results = True, verbose = False):
    """
    Trouve et retourne les lignes dupliquées basées sur un sous-ensemble de colonnes.

    Args:
        df (pd.DataFrame): Le DataFrame à vérifier.
        columns_to_check (list): Liste des colonnes définissant un duplicata.
        sort_results (bool): Si True, trie les résultats.
        verbose (bool): Si True, affiche le nombre de duplicatas trouvés.

    Returns:
        pd.DataFrame or None: Le DataFrame des duplicatas ou None si aucun n'est trouvé.
    """
    # Validation des inputs
    if columns_to_check:
        missing_cols = set(columns_to_check) - set(df.columns)
        if missing_cols:
            raise ValueError(f"Colonnes inexistantes: {missing_cols}")
    else:
        columns_to_check = df.columns.to_list()

    duplicates_mask = df.duplicated(subset=columns_to_check, keep=False)
    duplicate_rows = df[duplicates_mask].copy()
    
    if verbose:
        if duplicate_rows.empty:
            print("✅ Aucun doublon trouvé")
        else:
            try:
                n_groups = duplicate_rows.groupby(columns_to_check).ngroups
                print(f"🔍 {len(duplicate_rows)} lignes dupliquées ({n_groups} groupes)")
            except TypeError:
                print(f"🔍 {len(duplicate_rows)} lignes dupliquées (groupes non calculables)")
    
    return duplicate_rows.sort_values(by=columns_to_check) if sort_results and not duplicate_rows.empty else duplicate_rows
