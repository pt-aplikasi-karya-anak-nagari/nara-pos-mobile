# Dipakai skrip lain (source). Memastikan env/dev.json ada.
pastikan_env_dev() {
  if [ ! -f env/dev.json ]; then
    cp env/dev.example.json env/dev.json
    echo "• env/dev.json dibuat dari env/dev.example.json."
    echo "  Isi IP PC Anda: ./scripts/set_dev_ip.sh (atau edit manual)."
  fi
}

# Cetak isi berkas env (tanpa rahasia — memang tak ada rahasia di sana).
tampilkan_env() {
  echo "Memakai $1:"
  grep -E '"[A-Z_]+"' "$1" | sed -E 's/^ *"([A-Z_]+)": *"([^"]*)".*/  \1 = \2/'
}
