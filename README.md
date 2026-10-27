# 📶 5G Core Lab

A cloud-native **5G Standalone core** on Kubernetes with **three network slices** and **chaos tests**. **Open5GS** runs the core, **UERANSIM** simulates the gNB and phones, Prometheus + Grafana show live KPIs, and CI builds the whole network, attaches phones on every slice and then breaks things on purpose.

## Architecture

```
                         ┌──────────── shared control plane ────────────┐
                         │  AMF · NRF · SCP · NSSF · AUSF · UDM · UDR · PCF │
                         └───────┬───────────────┬────────────────┬──────┘
   Phones (UERANSIM)             │N2             │SBI             │SBI
   ───────────────── ┌────────┐  │        ┌──────┴─────┐   ┌──────┴─────┐   ┌────────────┐
   eMBB  ×3  ───────►│        │──┘        │ SMF-eMBB   │   │ SMF-URLLC  │   │ SMF-mMTC   │
   URLLC ×3  ───────►│  gNB   │           └─────┬──────┘   └─────┬──────┘   └─────┬──────┘
   mMTC  ×10 ───────►│ 3 slices│                │N4 (PFCP)       │N4              │N4
                     └───┬────┘           ┌─────┴──────┐   ┌─────┴──────┐   ┌─────┴──────┐
                         └── N3 (GTP-U) ─►│ UPF-eMBB   │   │ UPF-URLLC  │   │ UPF-mMTC   │
                                          │ 10.45/16   │   │ 10.46/16   │   │ 10.47/16   │
                                          └────────────┘   └────────────┘   └────────────┘
```

| Slice | S-NSSAI (SST/SD) | Use case | Phones | UE subnet |
|---|---|---|---|---|
| eMBB | 1 / 000001 | Enhanced mobile broadband | 3 | 10.45.0.0/16 |
| URLLC | 2 / 000002 | Ultra-reliable low latency | 3 | 10.46.0.0/16 |
| mMTC | 3 / 000003 | Massive IoT | 10 | 10.47.0.0/16 |

The control plane is shared. Each slice has its **own SMF and UPF**: the AMF and SCP pick the SMF from the S-NSSAI the phone asks for, so a failure in one slice's user plane stays in that slice.

## Quick start
Requirements: Docker, kind, kubectl, helm.

```bash
make up        # cluster + monitoring + core + per-slice SMF/UPF + gNB + phones
make test      # every phone registered, got an IP from ITS slice, reaches ITS UPF
make chaos     # kill AMF / eMBB UPF / URLLC SMF, measure outage per slice
make grafana   # http://localhost:3000 (admin/admin) → "5G Core - Network Slices"
make down
```

## Chaos experiments
`scripts/chaos.sh` keeps every slice's phones pinging their UPF through the GTP tunnel, kills one network function and reports how long each slice lost traffic:

| Experiment | What it shows |
|---|---|
| **Kill the AMF** | Control plane loss: do existing data sessions keep working? |
| **Kill the eMBB UPF** | Slice isolation: URLLC and mMTC should not notice |
| **Restart the URLLC SMF** | Session manager failure: does the user plane survive? |

### Findings
- **AMF loss doesn't stop sessions that are already up, but blocks new ones.** Data on established sessions keeps flowing while the AMF restarts. UERANSIM's gNB doesn't redo NG Setup with the new AMF, though, so no phone can register again until the gNB reconnects. A real gNB retries SCTP/NG Setup, which this lab does by restarting the gNB.
- **Slices are isolated.** Killing the eMBB UPF caused 0% loss on URLLC and mMTC.
- **A UPF restart needs operator action.** The SMF resolves its UPF's address once at startup, and a restarted UPF pod comes back with a new IP, so the slice stays down until its SMF is restarted and the phones re-attach. The chaos script does that and times it. In production you'd give the UPF a stable IP (e.g. Multus with a static address on N4/N3).
- **A replaced SMF breaks slice isolation.** After `smf-embb` was restarted (new NF instance), eMBB phones that re-attached got sessions from the **URLLC** SMF (10.46.x addresses). This kept happening even after the new eMBB SMF had registered with the NRF. The AMF/SCP keep selecting from the SMFs they already know, and nothing rejects a session from the wrong slice. Restarting the SCP and AMF clears it. In production: redundant SMFs per slice, and SMF selection strictly bound to the S-NSSAI.
- **PFCP needs a headless Service.** Through a ClusterIP, PFCP replies come back from the pod IP and the SMF drops them, so session modifications time out. Each UPF's PFCP Service is headless for that reason.

Every CI run writes the measured table to the job summary and uploads it as the `chaos-results` artifact.

## Layout
| Path | Purpose |
|---|---|
| `cluster/kind.yaml` | 3-node kind cluster |
| `helm/open5gs-values.yaml` | Shared core, slice list (AMF/NSSF) and subscribers per slice |
| `helm/slices/` | Per-slice SMF, UPF and phone values |
| `helm/ueransim-gnb-values.yaml` | gNB (patched to 3 slices by `scripts/gnb-add-slices.sh`) |
| `scripts/smoke-test.sh` | Per-slice attach + data test |
| `scripts/chaos.sh` | Chaos experiments and results table |
| `monitoring/` | kube-prometheus-stack values + Grafana dashboard |
| `.github/workflows/ci.yml` | Lint, full e2e and chaos run in kind |

## Roadmap
- [x] 5G SA core on Kubernetes with live KPIs
- [x] Network slicing (eMBB / URLLC / mMTC with dedicated SMF + UPF)
- [x] Chaos tests with per-slice outage measurement
- [ ] Per-slice QoS (5QI / AMBR) and throughput tests with iperf3
- [ ] Terraform module for a cloud cluster (EKS)
- [ ] IMS + VoNR, linking to [sip-voip-lab](https://github.com/TouficMad/sip-voip-lab)
- [ ] SMSF → [sms-gateway](https://github.com/TouficMad/sms-gateway) bridge

> Test PLMN (999/70) and test keys only. Not for production use.
