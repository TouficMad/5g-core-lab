# 📶 5G Core Lab

A cloud-native **5G Standalone core** running on Kubernetes: **Open5GS** (AMF, SMF, UPF, NRF, AUSF, UDM, PCF…) with **UERANSIM** simulating the gNB radio and phones (UEs). Includes Prometheus + Grafana for live KPIs and a CI pipeline that spins up the whole network and proves a UE can attach and pass traffic.

```
 UEs ──(Uu, simulated)── gNB ──N2 (NGAP/SCTP)── AMF ── AUSF/UDM/NRF/PCF
                          │                      │
                          └──N3 (GTP-U)── UPF ──N4 (PFCP)── SMF
                                           │
                                          N6 ──► Internet
```

## Quick start
Requirements: Docker, kind, kubectl, helm.

```bash
make up        # kind cluster + monitoring + 5G core + gNB/UEs
make test      # UE registers, gets a PDU session, pings 8.8.8.8 via the UPF
make ues N=100 # scale to 100 simulated phones
make grafana   # http://localhost:3000 (admin/admin) → "5G Core Overview"
make down
```

## Dashboards
Registered UEs · connected gNBs · active PDU sessions · registration success rate · UPF uplink/downlink throughput.

## Layout
| Path | Purpose |
|---|---|
| `cluster/kind.yaml` | 3-node cluster (core + RAN nodes) |
| `helm/` | Open5GS & UERANSIM values (PLMN 001/01, seeded subscribers) |
| `monitoring/` | kube-prometheus-stack values + Grafana dashboard |
| `scripts/smoke-test.sh` | End-to-end attach + data test |
| `.github/workflows/ci.yml` | Lint + full e2e in kind |

## Roadmap
- [ ] Terraform module for a cloud cluster (EKS)
- [ ] Network slicing (eMBB / URLLC / mMTC with separate SMF+UPF)
- [ ] Chaos tests: kill AMF/UPF and measure session recovery
- [ ] IMS + VoNR, linking to [sip-voip-lab](https://github.com/TouficMad/sip-voip-lab)
- [ ] SMSF → [sms-gateway](https://github.com/TouficMad/sms-gateway) bridge

> Test PLMN and keys only. Not for production use.
