#!/bin/bash

read -p "Inserisci il nome del file ISO di Windows completo di estensione (es. windows10.iso): " ISO_NAME
while [[ ! -f "$ISO_NAME" ]]; do
    echo "Errore: il file $ISO_NAME non esiste. Inserisci un nome valido. Assicurati che $ISO_NAME sia nella stessa directory."
    read -p "Inserisci il nome del file ISO di Windows completo di estensione (es. windows10.iso): " ISO_NAME
done

read -p "Inserisci l'ID della VM (es. 100): " VM_ID
while [[ ! "$VM_ID" =~ ^[0-9]+$ || "$VM_ID" -lt 100 || "$VM_ID" -gt 9999999 || $(qm list | awk '{print $1}' | grep -w "$VM_ID") ]]; do    if [[ $(qm list | awk '{print $1}' | grep -w "$VM_ID") ]]; then
        echo "Errore: esiste già una VM con ID $VM_ID. Scegli un ID diverso."
    else
        echo "Errore: inserisci un numero intero valido per l'ID della VM."
    fi
    read -p "Inserisci l'ID della VM (es. 100): " VM_ID
done

read -p "Inserisci la quantità di RAM in MB (es. 4096): " RAM_SIZE_MB
while [[ ! "$RAM_SIZE_MB" =~ ^[0-9]+$ || "$RAM_SIZE_MB" -lt 2048 ]]; do
    echo "Errore: inserisci un valore intero valido per la RAM (almeno 2048 MB)."
    read -p "Inserisci la quantità di RAM in MB (es. 4096): " RAM_SIZE_MB
done

read -p "Inserisci il numero di core (es. 2): " CORE_COUNT
while [[ ! "$CORE_COUNT" =~ ^[0-9]+$ || "$CORE_COUNT" -lt 1 ]]; do
    echo "Errore: inserisci un numero intero valido per i core (almeno 1 core)."
    read -p "Inserisci il numero di core (es. 2): " CORE_COUNT
done

read -p "Inserisci la dimensione del disco in GB (es. 60 - Il minimo indispensabile per FlareVM): " DISK_SIZE_GB
while [[ ! "$DISK_SIZE_GB" =~ ^[0-9]+$ || "$DISK_SIZE_GB" -lt 60 ]]; do
    echo "Errore: inserisci un valore intero valido per la dimensione del disco (almeno 60 GB)."
    read -p "Inserisci la dimensione del disco in GB (es. 60 - Il minimo indispensabile per FlareVM): " DISK_SIZE_GB
done

CUSTOM_ISO_NAME="custom_windows.iso"
XML_FILE="autounattend.xml"
VIRTIO_ISO="virtio-win.iso"

if [ ! -f "$XML_FILE" ]; then
    echo "Errore: file Autounattend.xml non trovato. Assicurati che $XML_FILE sia nella stessa directory."
    exit 1
fi

mkdir -p /mnt/windows_iso
mkdir -p windows_iso_content

mount -o loop "$ISO_NAME" /mnt/windows_iso || { echo "Errore nel montaggio dell'ISO"; exit 1; }

cp -r /mnt/windows_iso/* windows_iso_content/ || { echo "Errore nella copia del contenuto dell'ISO"; exit 1; }
umount /mnt/windows_iso
cp "$XML_FILE" windows_iso_content/

echo "Creazione della ISO personalizzata con autounattend.xml..."

genisoimage -allow-limited-size -o "$CUSTOM_ISO_NAME" -R -J -no-emul-boot -b boot/etfsboot.com -c boot.cat -boot-load-seg 0x07C0 -boot-load-size 8 windows_iso_content

if [ ! -f "$CUSTOM_ISO_NAME" ]; then
  echo "Errore nella creazione della ISO personalizzata!"
  exit 1
fi

rm -rf windows_iso_content

echo "Caricamento della ISO su Proxmox..."
mv "$CUSTOM_ISO_NAME" /var/lib/vz/template/iso/ || { echo "Errore nel caricamento della ISO su Proxmox"; exit 1; }

if [ ! -f "/var/lib/vz/template/iso/$VIRTIO_ISO" ]; then
    echo "Scaricamento della ISO dei driver Virtio..."
    wget -q "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/$VIRTIO_ISO"
    if [ $? -ne 0 ]; then
        echo "Errore nel download della ISO dei driver Virtio."
        exit 1
    fi

    echo "Caricamento della ISO dei driver Virtio su Proxmox..."
    mv "$VIRTIO_ISO" /var/lib/vz/template/iso/ || { echo "Errore nel caricamento della ISO su Proxmox"; exit 1; }
else
    echo "La ISO dei driver Virtio è già presente in /var/lib/vz/template/iso, procedo con la creazione della VM..."
fi

echo "Creazione della VM su Proxmox e aggiunta dei driver virtio..."

qm create "$VM_ID" \
    --cdrom local:iso/$CUSTOM_ISO_NAME \
    --ide3 local:iso/$VIRTIO_ISO,media=cdrom \
    --name "WindowsVM" \
    --memory "$RAM_SIZE_MB" \
    --cores "$CORE_COUNT" \
    --scsihw virtio-scsi-pci \
    --ostype win10 \
    --agent 1 \
    --cpu x86-64-v2-AES \
    --net0 virtio,bridge=vmbr0,firewall=1 \
    --numa 0 \
    --scsi0 local-lvm:"$DISK_SIZE_GB",iothread=on,cache=writeback \

qm start "$VM_ID"
echo "La VM con ID $VM_ID è stata creata e avviata. Segui l'installazione guidata di Windows."
