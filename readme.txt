Voici la **documentation intégrale, exhaustive et technique** de l'application **Agro Pass 2026**. Elle regroupe tous les aspects : architecture, base de données, logique par page et sécurité, en intégrant vos derniers réglages réels.

---

# 📱 **DOCUMENTATION COMPLÈTE : APPLICATION AGRO PASS 2026**

## **1. PRÉSENTATION DU PROJET**
* **Nom du Projet :** AGRO PASS
* **ID Firebase :** `agro-pass`
* **Objectif :** Gestion des flux, paiements et contrôles d'accès pour l'événement universitaire "Agro 2026".
* **Localisation :** Fianarantsoa, Madagascar.

---

## **2. ARCHITECTURE TECHNIQUE (BACKEND)**

### **2.1. Authentification (Firebase Auth)**
L'accès est restreint à deux profils spécifiques créés le 29 mars 2026 :
* **Admin :** `admin_agro@gmail.com` (UID: `l7tsJzOnAzbiFHJjxiVdwAdR2xi2`)
* **Vérificateur :** `agro_scan@gmail.com` (UID: `v1sbILGGhVYMaVkEz2zEH9JyGp63`)

### **2.2. Structure Firestore (NoSQL)**

#### **A. Collection `user` (au singulier)**
*Chaque document a pour ID l'UID de l'utilisateur.*
* **Document Admin :** `{ display_name: "Administrateur", role: "admin", username: "admin_agro@gmail.com" }`
* **Document Verifier :** `{ display_name: "Agent de vérification", role: "verifier", username: "agro_scan@gmail.com" }`

#### **B. Collection `students` (460 documents)**
*L'ID du document est le **matricule** (ex: `1002`).*
* **Champs :**
    * `matricule` (String), `nom` (String), `prenom` (String)
    * `niveau` (L1, L2, L3, M1), `parcours` (3COM, IAAB, PA, PV)
    * `has_paid` (Boolean) : Indique si le paiement est reçu.
    * `qr_code_generated` (Boolean) : Badge généré ou non.
    * `qr_code_scanned` (Boolean) : Présence validée à l'entrée.
    * `photo` (Base64) : Photo d'identité.

#### **C. Collection `counters` (Statistiques)**
*Document unique `stats` gérant **46 compteurs** en temps réel :*
* **Général :** `total_students`, `total_paid`, `total_scanned`.
* **Par Niveau :** `L1_total`, `L1_paid`, `L1_scanned`, etc.
* **Par Parcours :** `3COM_total`, `3COM_paid`, `PA_scanned`, etc.
* **Combinés :** `L2_PA_total`, `L3_IAAB_scanned`, etc.

---

## **3. DESCRIPTION DÉTAILLÉE DES PAGES**

### **Page 1 : Authentification (Login)**
* **Visuels :** Logo Agro, champs de saisie épurés, bouton vert "Se Connecter".
* **Fonctionnalité :**
    * Vérification des identifiants via Firebase Auth.
    * Lecture immédiate du document correspondant dans la collection `user`.
    * **Routage intelligent :** Redirige vers le Dashboard complet pour l'admin, ou directement vers le Scanner pour le vérificateur.

### **Page 2 : Dashboard & Liste (Admin Uniquement)**
* **Barre de Statistiques (Header) :** Affiche 3 compteurs dynamiques (Total / Payés / Entrés). Les chiffres changent selon les filtres.
* **Système de Filtres :**
    * Filtre par **Niveau** (L1 à M1).
    * Filtre par **Parcours** (3COM, IAAB, PA, PV).
    * Barre de recherche textuelle (Nom ou Matricule).
* **Liste des Étudiants :**
    * Codes couleurs : ⚪ (Inconnu), 🟢 (Payé/Badge prêt), 🟠 (Entré/Scanné).
* **Fiche Étudiant (Modal) :** S'ouvre au clic. Permet de :
    * Prendre une photo (Caméra mobile).
    * Cocher `has_paid` (déclenche l'incrémentation des stats `_paid`).
    * Générer le QR Code : crée une image contenant `{matricule}_{niveau}_{parcours}`.

### **Page 3 : Scanner QR Code (Admin & Vérificateur)**
* **Visuels :** Flux caméra en direct avec viseur central.
* **Logique de contrôle :**
    1.  Lecture du QR.
    2.  Récupération du matricule.
    3.  **Fenêtre de confirmation :** Affiche le nom, prénom et la photo de l'étudiant.
    4.  **Action :** Bouton "Valider l'entrée".
    * *Sécurité :* Si `qr_code_scanned` est déjà à `true`, affiche un message d'alerte rouge **"ACCÈS DÉJÀ VALIDÉ"**.

### **Page 4 : Recherche ID (Admin & Vérificateur)**
* **Fonctionnalité :** Solution de secours. Saisie manuelle du matricule si le QR code est illisible.
* **Logique :** Si le matricule existe et que `qr_code_generated` est vrai, l'application propose de valider l'entrée manuellement.

---

## **4. WORKFLOW TECHNIQUE (OPÉRATIONNEL)**

1.  **Enregistrement :** L'admin valide le paiement d'un étudiant L1.
    * *Action Firestore :* `has_paid = true`, `L1_paid +1`, `total_paid +1`.
2.  **Contrôle :** L'agent de vérification scanne le badge à l'entrée.
    * *Action Firestore :* `qr_code_scanned = true`, `L1_scanned +1`, `total_scanned +1`.
3.  **Ajout M1 :** L'admin peut ajouter manuellement un étudiant M1 (non présent dans l'import initial).
    * *Action Firestore :* Création d'un nouveau document dans `students` + mise à jour de `total_students +1`.

---

## **5. SÉCURITÉ ET RÈGLES**
* **Atomicité :** Utilisation de `FieldValue.increment()` pour éviter les conflits si 10 agents scannent en même temps.
* **Intégrité :** Le vérificateur ne peut **jamais** modifier le statut de paiement ou les noms des étudiants.
* **Persistance :** Les données sont synchronisées dès que la connexion (4G/Wifi) est rétablie.

---

**Souhaitez-vous que je rédige maintenant le script d'importation automatique pour vos 460 étudiants dans Firestore ?**