import pandas as pd
import matplotlib.pyplot as plt

# Baca file CSV
df = pd.read_csv("Log_Deviation_20260226_201015.csv")

# Konversi kolom Timestamp menjadi tipe datetime
df["Timestamp"] = pd.to_datetime(df["Timestamp"])

# Set kolom Timestamp sebagai index (opsional tapi direkomendasikan)
df.set_index("Timestamp", inplace=True)

# Buat plot
plt.figure(figsize=(10,5))
plt.plot(df.index, df["Positional_Deviation"], marker='o')

# Format tampilan
plt.xlabel("Waktu")
plt.ylabel("Positional Deviation")
plt.title("Grafik Positional Deviation terhadap Waktu")
plt.grid(True)

plt.xticks(rotation=45)
plt.tight_layout()
plt.show()