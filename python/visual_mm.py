import pandas as pd
import matplotlib.pyplot as plt

# Parameter sistem
PPR = 2500
LEAD_MM = 10  # mm per rotation

MM_PER_PULSE = LEAD_MM / PPR

# Baca file CSV
df = pd.read_csv("Log_Deviation_20260226_201015.csv")

# Konversi timestamp
df["Timestamp"] = pd.to_datetime(df["Timestamp"])

# Konversi pulse ke mm
df["Deviation_mm"] = df["Positional_Deviation"] * MM_PER_PULSE

# Set timestamp sebagai index
df.set_index("Timestamp", inplace=True)

# Plot
plt.figure(figsize=(10,5))
plt.plot(df.index, df["Deviation_mm"], marker='o')

plt.xlabel("Waktu")
plt.ylabel("Deviasi (mm)")
plt.title("Grafik Deviasi Posisi terhadap Waktu")
plt.grid(True)
plt.xticks(rotation=45)
plt.tight_layout()
plt.show()