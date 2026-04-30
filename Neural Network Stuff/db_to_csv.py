import sqlite3
import csv


def export_to_csv(db_path, csv_path):
    """
    Export the contents of the feeding_rate table to a CSV file.
    """
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Query the table
    cursor.execute("SELECT * FROM feeding_rate;")
    rows = cursor.fetchall()

    # Get column names
    cursor.execute("PRAGMA table_info(feeding_rate);")
    columns = [col[1] for col in cursor.fetchall()]

    # Write to CSV
    with open(csv_path, mode='w', newline='', encoding='utf-8') as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(columns)  # Write header
        writer.writerows(rows)    # Write rows

    print(f"Data exported to {csv_path}")

    conn.close()


def print_db_contents(DB_PATH):
    """
    Print the contents of the feeding_rate table for verification.
    """
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Show tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    print("Tables:", cursor.fetchall())

    # Show row count
    cursor.execute("SELECT COUNT(*) FROM feeding_rate;")
    print("Row count:", cursor.fetchone()[0])

    # Show actual contents
    cursor.execute("SELECT * FROM feeding_rate;")
    rows = cursor.fetchall()

    print("\n--- DB CONTENTS ---")
    for row in rows:
        print(row)

    conn.close()


# Main Excution
DB_PATH = "/Users/tabathaguebard/Desktop/Bite-to-byte Neural Network/feeding_rates.db"
CSV_PATH = "/Users/tabathaguebard/Desktop/Bite-to-byte Neural Network/feeding_rates.csv"

export_to_csv(DB_PATH, CSV_PATH)
print_db_contents(DB_PATH)