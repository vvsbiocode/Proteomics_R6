#!/bin/bash

LOCAL_TPP="/usr/local/tpp/bin"
RERUN=false #comet rerun

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <batch_number>"
    echo "Example: $0 1"
    exit 1
fi

BATCH_NUM=$1
WD=$(pwd)
BATCH_DIR="${WD}/data/batch${BATCH_NUM}"

echo "Copy all raw and mzml files into ./data/batch${BATCH_NUM}" #not clean but whatever
mkdir -p "$BATCH_DIR/raw"
mkdir -p "$BATCH_DIR/mzml"
mkdir -p "$BATCH_DIR/database"
mkdir -p "$BATCH_DIR/search"
mkdir -p "$BATCH_DIR/results"

for f in ./PXD007160/raw/*; do
    [ -e "$BATCH_DIR/raw/$(basename "$f")" ] || cp "$f" "$BATCH_DIR/raw/"
done

for f in ./PXD007160/mzml/*; do
    [ -e "$BATCH_DIR/mzml/$(basename "$f")" ] || cp "$f" "$BATCH_DIR/mzml/"
done

echo "Processing batch${BATCH_NUM}"

echo "Batch directory: ${BATCH_DIR}"

if ! compgen -G "${BATCH_DIR}/mzml/*.mzML" > /dev/null
then
    echo "No mzML files found"
    exit 1
fi

########################################
# Download database if missing
########################################

DB="${BATCH_DIR}/database/UP000005640_9606.fasta"

if [ ! -f "${DB}" ]; then

    echo "Downloading UniProt human proteome"

    wget \
    https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/reference_proteomes/Eukaryota/UP000005640/UP000005640_9606.fasta.gz \
    -O "${BATCH_DIR}/database/UP000005640_9606.fasta.gz"

    gunzip "${BATCH_DIR}/database/UP000005640_9606.fasta.gz"
fi

########################################
# Create Comet parameters
########################################

cd "${BATCH_DIR}/search"

echo "Creating Comet parameters"

$LOCAL_TPP/comet -p

PARAMS="comet.params.new"

sed -i "s|^database_name =.*|database_name = ${DB}|" ${PARAMS}
sed -i "s|^decoy_search =.*|decoy_search = 1|" ${PARAMS}
sed -i "s|^isotope_error =.*|isotope_error = 3|" ${PARAMS}

sed -i "s|^peptide_mass_tolerance =.*|peptide_mass_tolerance = 20.0|" ${PARAMS}
sed -i "s|^peptide_mass_units =.*|peptide_mass_units = 2|" ${PARAMS}

sed -i "s|^fragment_bin_tol =.*|fragment_bin_tol = 1.0005|" ${PARAMS}
sed -i "s|^fragment_bin_offset =.*|fragment_bin_offset = 0.4|" ${PARAMS}

sed -i "s|^allowed_missed_cleavage =.*|allowed_missed_cleavage = 2|" ${PARAMS}

sed -i "s|^add_C_cysteine =.*|add_C_cysteine = 57.021464|" ${PARAMS}
sed -i "s|^add_K_lysine =.*|add_K_lysine = 229.162932|" ${PARAMS}
sed -i "s|^add_Nterm_peptide =.*|add_Nterm_peptide = 229.162932|" ${PARAMS}

sed -i 's/^variable_mod01.*/variable_mod01 = 15.994915 M 0 3 -1 0 0/' ${PARAMS}
sed -i 's/^variable_mod02.*/variable_mod02 = 0.984016 NQ 0 3 -1 0 0/' ${PARAMS}

########################################
# Run Comet
########################################

echo "Running Comet"

for file in "${BATCH_DIR}"/mzml/*.mzML
do

   base="${file%.mzML}"
   pepxml="${base}.pep.xml"
   echo "Processing $(basename "$file")"

    if [ "$RERUN" = "true" ] || [ ! -f "$pepxml" ]; then
        $LOCAL_TPP/comet -P"${PARAMS}" "$file"
    else
        echo "Skipping $(basename "$file"): $pepxml already exists or rerun is disabled"
    fi

done

########################################
# Create Libra configuration
########################################

echo "Creating Libra configuration"

COND_LIBRA=$BATCH_DIR/search/libra_condition.xml
touch $COND_LIBRA

########################################
# Create Libra configuration
########################################

echo "Creating Libra configuration"

cat <<EOF > $COND_LIBRA
<?xml version="1.0" encoding="UTF-8"?>
<SUMmOnCondition description="TMT-10plex-AD-PD-Brain-Tissue">
  <fragmentMasses>
    <reagent mz="126.1277"/>
    <reagent mz="127.1248"/>
    <reagent mz="127.1311"/>
    <reagent mz="128.1281"/>
    <reagent mz="128.1344"/>
    <reagent mz="129.1315"/>
    <reagent mz="129.1378"/>
    <reagent mz="130.1348"/>
    <reagent mz="130.1411"/>
    <reagent mz="131.1382"/>
  </fragmentMasses>
  <massTolerance value="0.001"/>
  <centroiding type="2" iterations="1"/>
  <normalization type="1"/>
  <targetMs level="2"/>
  <output type="1"/>
  <quantitationFile name="quantitation.tsv"/>
  <minimumThreshhold value="20"/>
</SUMmOnCondition>
EOF

########################################
# PeptideProphet + Libra
########################################

echo "Running PeptideProphet + Libra"

#xinteract \
#-N"${BATCH_DIR}/results/interact.pep.xml" \
#-OAP \
#-L"${BATCH_DIR}/search/libra_condition.xml" \
#"${BATCH_DIR}"/mzml/*.pep.xml

$LOCAL_TPP/xinteract \
-N"${BATCH_DIR}/results/interact.pep.xml" \
-L"${BATCH_DIR}/search/libra_condition.xml" \
-Op \
"${BATCH_DIR}"/mzml/*.pep.xml

########################################
# ProteinProphet
########################################

# echo "Running ProteinProphet"

# ProteinProphet \
# "${BATCH_DIR}/results/interact.pep.xml" \
# "${BATCH_DIR}/results/interact.prot.xml"

########################################
# Export for R
########################################

#echo "Exporting for R"

#cd "${BATCH_DIR}/results"

#idconvert interact.pep.xml

#sed 's|http://psidev.info/psi/pi/mzIdentML/1.2|http://psidev.info/psi/pi/mzIdentML/1.1|g' frontalcortex_batch1_fraction01.mzid > interact.pep_Rcompatible.mzid

echo "Done"
