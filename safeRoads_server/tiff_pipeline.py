import os
import requests
from tqdm import tqdm
import subprocess
import sys
import psycopg2
from dotenv import load_dotenv

BASE_URL = "https://www.natureforecast.org/natureforecast.org/maps_forecasts_via_ftp/"
FILE_NAME = "predictions_T1.tiff"
DOWNLOAD_DIR = os.path.join(os.path.dirname(__file__), "downloads")
TIFF_PATH = os.path.join(DOWNLOAD_DIR, FILE_NAME)

load_dotenv()
DB_USER = os.getenv('DB_USER')
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_PASSWORD = os.getenv('DB_PASSWORD')
DB_PORT = os.getenv('DB_PORT')

def download_tiff():
    os.makedirs(DOWNLOAD_DIR, exist_ok=True)
    file_url = BASE_URL + FILE_NAME
    print(f"Downloading {FILE_NAME}...")

    try:
        with requests.get(file_url, stream=True) as r:
            r.raise_for_status()
            with open(TIFF_PATH, "wb") as f:
                total = int(r.headers.get('content-length', 0))
                with tqdm(total=total, unit='B', unit_scale=True, desc="Downloading") as pbar:
                    for chunk in r.iter_content(chunk_size=8192):
                        f.write(chunk)
                        pbar.update(len(chunk))
        print(f"Download complete: {TIFF_PATH}")
    except Exception as e:
        print(f"Download failed: {e}")
        sys.exit(1)

def import_to_postgres(raster_path):
    if not os.path.exists(raster_path):
        print("TIFF file not found.")
        return

    print("Importing into Postgres...")
    command = [
        "raster2pgsql",
        "-s", "4326",
        "-t", "100x100",
        "-d",
        "-k",
        "-C",
        "-I",
        "-M",
        raster_path,
        "public.amphibians"
    ]
    # Created a file for linux so that is doenst prompt the pass in the cmd
    psql_command = "| psql -U postgres -d saferoads -h localhost -p 5432"
    full_command = " ".join(command) + " " + psql_command

    file_size = os.path.getsize(raster_path)
    total_mb = file_size / (1024 * 1024)

    process = subprocess.Popen(full_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    with tqdm(total=total_mb, desc="Processing Raster", unit="MB") as pbar:
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            pbar.update(1)

    process.wait()
    if process.returncode != 0:
        print(f"Error: {process.stderr.read()}")
    else:
        print("Import complete.")

def materialize_species_risks():
    print("Materializing species risk values...")

    # Species list (update as needed)
    # SPECIES = ["amphibians", "reptiles", "hedgehogs"]
    # SPECIES = ["amphibians", "reptiles"]
    SPECIES = ["amphibians"]

    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT
        )
        cur = conn.cursor()

        cur.execute("""
            DROP TABLE IF EXISTS species_risk_by_way;
            CREATE TABLE species_risk_by_way (
                gid INTEGER,
                species TEXT,
                risk_value DOUBLE PRECISION
            );
        """)

        # Create indices for improved query performance
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_species_risk_gid ON species_risk_by_way(gid);
            CREATE INDEX IF NOT EXISTS idx_species_risk_species ON species_risk_by_way(species);
            CREATE INDEX IF NOT EXISTS idx_species_risk_gid_species ON species_risk_by_way(gid, species);
        """)

        for species in SPECIES:
            print(f"Processing species: {species}")
            cur.execute(f"""
                INSERT INTO species_risk_by_way (gid, species, risk_value)
                SELECT
                    w.gid,
                    '{species}' AS species,
                    COALESCE(ST_Value(r.rast, 1, ST_Centroid(w.the_geom)), 0)
                FROM ways w
                JOIN {species} r
                ON ST_Intersects(r.rast, w.the_geom);
            """)

        conn.commit()
        cur.close()
        conn.close()
        print("Species risk values materialized.")

    except Exception as e:
        print(f"Error during materialization: {e}")
        sys.exit(1)

def create_get_ways_with_risk_function():
    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD, 
            host=DB_HOST,
            port=DB_PORT
        )
        cur = conn.cursor()

        create_function_sql = """
        CREATE OR REPLACE FUNCTION get_ways_with_risk(selected_species TEXT[])
        RETURNS TABLE (
            gid BIGINT,
            source BIGINT,
            target BIGINT,
            the_geom geometry,
            maxspeed_forward DOUBLE PRECISION,
            maxspeed_backward DOUBLE PRECISION,
            risk_value DOUBLE PRECISION,
            species TEXT[],
            cost DOUBLE PRECISION,
            reverse_cost DOUBLE PRECISION,
            length_m DOUBLE PRECISION 
        ) AS $$
        BEGIN
            RETURN QUERY
            SELECT
                w.gid,
                w.source,
                w.target,
                w.the_geom,
                w.maxspeed_forward,
                w.maxspeed_backward,
                COALESCE(sr.max_risk, 0) AS risk_value,
                sr.species AS species,
                w.cost,
                w.reverse_cost,
                w.length_m 
            FROM ways w
            LEFT JOIN (
                SELECT
                    srbw.gid,
                    MAX(srbw.risk_value) AS max_risk,
                    ARRAY_AGG(DISTINCT srbw.species) AS species
                FROM species_risk_by_way srbw
                WHERE selected_species IS NULL OR srbw.species = ANY(selected_species)
                GROUP BY srbw.gid
            ) sr ON w.gid = sr.gid;
        END;
        $$ LANGUAGE plpgsql;
        """

        cur.execute(create_function_sql)
        conn.commit()
        cur.close()
        conn.close()
        print("Function get_ways_with_risk created or replaced.")

    except Exception as e:
        print(f"Error creating function: {e}")

if __name__ == "__main__":
    download_tiff()
    projected_path = os.path.join(DOWNLOAD_DIR, "predictions_T1.tiff")
    import_to_postgres(projected_path)
    materialize_species_risks()
    create_get_ways_with_risk_function() 
