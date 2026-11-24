# shellcheck shell=bash
# =============================================================================
# Zustand und Downgrade-Regel fuer den Pull-Deploy auf Staging (ADR-017,
# E-5-146, E-5-147). Bibliothek: wird per "source" geladen und setzt beim
# Laden nur Konstanten.
#
# Einstiege:
#   scripts/fetch-release.sh        Server: Freigabe pruefen, entscheiden,
#                                   Dateien aus dem Bundle holen (PR 4c)
#   scripts/test-release-state.sh   Faelle fuer Bibliothek und Einstieg
#
# Warum eine eigene Bibliothek: Die Entscheidung ist reine Logik ohne Netz
# und ohne Docker. Getrennt davon laesst sie sich Zeile fuer Zeile gegen die
# Tabelle aus ADR-017 testen, lokal und in der CI. Eine neue Regel ist ein
# neuer Zweig plus ein neuer Testfall; der Ablauf im Einstieg bleibt.
#
# Kein exit in dieser Datei: Die Funktionen melden ueber den Rueckgabewert
# und stderr; der Einstieg entscheidet, wie er abbricht.
#
# Format der Zustandsdatei (genau drei Zeilen, je mit Zeilenende):
#   run<TAB><Run-ID>
#   commit<TAB><40 hex>
#   bundle<TAB>sha256:<64 hex>
# Geschrieben wird sie erst nach erfolgreichem Deploy (PR 4d), und zwar nur
# ueber release_state_render, damit Lesen und Schreiben dasselbe Format
# haben (eine Quelle der Wahrheit).
# =============================================================================

# Obergrenze fuer die Groesse der Zustandsdatei. Drei Zeilen brauchen unter
# 200 Bytes; alles darueber ist kein Zustand von uns.
readonly RELEASE_STATE_MAX_BYTES=1024

# --- Formen der Werte ---------------------------------------------------------
# Run-ID: hoechstens 18 Ziffern, ohne fuehrende Null. 18 Ziffern liegen sicher
# unter der Grenze der Bash-Arithmetik (64 Bit, 19 Ziffern), heutige IDs
# haben 11. Erst NACH dieser Pruefung wird gerechnet: $(( )) wertet Ausdruecke
# aus, ein Wert wie a[$(befehl)] wuerde sonst einen Befehl ausfuehren.
release_state_valid_run() {
  [[ "${1-}" =~ ^[1-9][0-9]{0,17}$ ]]
}
release_state_valid_commit() {
  [[ "${1-}" =~ ^[0-9a-f]{40}$ ]]
}
release_state_valid_bundle() {
  [[ "${1-}" =~ ^sha256:[0-9a-f]{64}$ ]]
}

# release_state_render RUN COMMIT BUNDLE
# Gibt den Inhalt der Zustandsdatei auf stdout aus. Ungueltige Werte: nichts
# auf stdout, Grund auf stderr, Rueckgabe 1.
release_state_render() {
  [ "$#" -eq 3 ] || { echo "Zustand: erwartet RUN COMMIT BUNDLE" >&2; return 1; }
  release_state_valid_run "$1" || { echo "Zustand: ungueltige Run-ID" >&2; return 1; }
  release_state_valid_commit "$2" || { echo "Zustand: ungueltiger Commit" >&2; return 1; }
  release_state_valid_bundle "$3" || { echo "Zustand: ungueltiger Bundle-Digest" >&2; return 1; }
  printf 'run\t%s\ncommit\t%s\nbundle\t%s\n' "$1" "$2" "$3"
}

# release_state_parse DATEI
# Liest eine VORHANDENE Zustandsdatei und setzt STATE_RUN, STATE_COMMIT,
# STATE_BUNDLE. Jede Abweichung (Link, keine gewoehnliche Datei, unlesbar,
# zu gross, leer, falsche Zeilen, fehlendes Zeilenende) ergibt Rueckgabe 1
# mit Grund auf stderr.
#
# Wichtig (CLAUDE.md Abschnitt 7): Eine kaputte Datei ist NICHT "kein
# Zustand". Sonst wuerde ein vorhandener Erst-Schalter einen Deploy ohne
# Vergleich ausloesen, und der Downgrade-Schutz waere ausgehebelt. Ob die
# Datei fehlt, entscheidet der Aufrufer VOR diesem Aufruf.
release_state_parse() {
  local file="${1-}" size line n=0 key value
  STATE_RUN=""
  STATE_COMMIT=""
  STATE_BUNDLE=""
  [ -n "${file}" ] || { echo "Zustand: kein Pfad" >&2; return 1; }
  [ ! -L "${file}" ] || { echo "Zustand: ist ein symbolischer Link" >&2; return 1; }
  [ -f "${file}" ] || { echo "Zustand: keine gewoehnliche Datei" >&2; return 1; }
  [ -r "${file}" ] || { echo "Zustand: nicht lesbar" >&2; return 1; }
  size="$(wc -c <"${file}")" || { echo "Zustand: Groesse nicht lesbar" >&2; return 1; }
  size="${size//[[:space:]]/}"
  [[ "${size}" =~ ^[0-9]+$ ]] || { echo "Zustand: Groesse nicht lesbar" >&2; return 1; }
  [ "${size}" -gt 0 ] || { echo "Zustand: leer" >&2; return 1; }
  [ "${size}" -le "${RELEASE_STATE_MAX_BYTES}" ] || { echo "Zustand: zu gross" >&2; return 1; }

  local -a want=(run commit bundle)
  while IFS= read -r line; do
    [ "${n}" -lt 3 ] || { echo "Zustand: mehr als drei Zeilen" >&2; return 1; }
    [[ "${line}" == *$'\t'* ]] || { echo "Zustand: Zeile $((n + 1)) ohne Tabulator" >&2; return 1; }
    key="${line%%$'\t'*}"
    value="${line#*$'\t'}"
    [ "${key}" = "${want[$n]}" ] \
      || { echo "Zustand: Zeile $((n + 1)) muss mit ${want[$n]} beginnen" >&2; return 1; }
    case "${key}" in
      run) release_state_valid_run "${value}" || { echo "Zustand: ungueltige Run-ID" >&2; return 1; }
        STATE_RUN="${value}" ;;
      commit) release_state_valid_commit "${value}" || { echo "Zustand: ungueltiger Commit" >&2; return 1; }
        STATE_COMMIT="${value}" ;;
      bundle) release_state_valid_bundle "${value}" || { echo "Zustand: ungueltiger Bundle-Digest" >&2; return 1; }
        STATE_BUNDLE="${value}" ;;
    esac
    n=$((n + 1))
  done <"${file}"
  # read liefert bei einer letzten Zeile ohne Zeilenende "falsch", setzt sie
  # aber in line. Eine solche Zeile ist abgeschnitten: ungueltig.
  [ -z "${line-}" ] || { echo "Zustand: letzte Zeile ohne Zeilenende" >&2; return 1; }
  [ "${n}" -eq 3 ] || { echo "Zustand: erwartet drei Zeilen, gefunden ${n}" >&2; return 1; }
}

# release_decide ZUSTAND STATE_RUN STATE_COMMIT NEW_RUN NEW_COMMIT SCHALTER
#   ZUSTAND   none (Datei fehlt) | valid (gelesen) | invalid (vorhanden,
#             aber nicht lesbar oder ungueltig)
#   SCHALTER  yes | no (Erst-Schalter vorhanden und vom Einstieg geprueft)
# Gibt genau ein Wort auf stdout aus:
#   deploy  neuere Freigabe
#   first   erster Deploy ohne Vergleich (kein Zustand, Schalter vorhanden)
#   noop    dieselbe Freigabe wie gespeichert
#   reject  ablehnen und alarmieren
# Gruende und Warnungen auf stderr. Unbekannte oder ungueltige Eingaben
# ergeben reject (fail closed). Rueckgabe immer 0, damit "$( )" das Wort
# auch bei set -e liefert.
#
# Tabelle aus ADR-017 (Downgrade-Regel und Erst-Schalter):
#   Run-ID groesser als gespeichert                  deploy
#   gleiche Run-ID, gleicher Commit                  noop
#   kleinere Run-ID oder gleiche mit anderem Commit  reject
#   kein Zustand, kein Schalter                      reject
#   kein Zustand, Schalter vorhanden                 first
#   Zustand vorhanden, Schalter vorhanden            Schalter ignorieren,
#                                                    Warnung, Vergleich gilt
release_decide() {
  if [ "$#" -ne 6 ]; then
    echo "Grund: release_decide erwartet sechs Parameter" >&2
    echo reject
    return 0
  fi
  local kind="$1" s_run="$2" s_commit="$3" n_run="$4" n_commit="$5" switch="$6"

  case "${switch}" in
    yes | no) ;;
    *) echo "Grund: Schalter-Angabe ungueltig" >&2; echo reject; return 0 ;;
  esac
  if ! release_state_valid_run "${n_run}" || ! release_state_valid_commit "${n_commit}"; then
    echo "Grund: Freigabe hat keine gueltige Run-ID oder keinen gueltigen Commit" >&2
    echo reject
    return 0
  fi

  case "${kind}" in
    none)
      if [ "${switch}" = "yes" ]; then
        echo "Warnung: kein Zustand, Erst-Schalter vorhanden - erster Deploy ohne Vergleich" >&2
        echo first
      else
        echo "Grund: kein Zustand und kein Erst-Schalter" >&2
        echo reject
      fi
      return 0
      ;;
    invalid)
      echo "Grund: Zustand vorhanden, aber nicht lesbar oder ungueltig" >&2
      echo reject
      return 0
      ;;
    valid) ;;
    *) echo "Grund: Zustands-Angabe ungueltig" >&2; echo reject; return 0 ;;
  esac

  if ! release_state_valid_run "${s_run}" || ! release_state_valid_commit "${s_commit}"; then
    echo "Grund: gespeicherter Zustand ungueltig" >&2
    echo reject
    return 0
  fi
  if [ "${switch}" = "yes" ]; then
    echo "Warnung: Erst-Schalter wird ignoriert, weil Zustand existiert; bitte von Hand loeschen" >&2
  fi

  # Beide Werte sind hier geprueft (nur Ziffern, ohne fuehrende Null).
  if (( n_run > s_run )); then
    echo deploy
  elif (( n_run < s_run )); then
    echo "Grund: Run-ID ${n_run} ist kleiner als gespeichert (${s_run}) - Downgrade" >&2
    echo reject
  elif [ "${n_commit}" = "${s_commit}" ]; then
    echo noop
  else
    echo "Grund: gleiche Run-ID ${n_run} mit anderem Commit" >&2
    echo reject
  fi
  return 0
}
