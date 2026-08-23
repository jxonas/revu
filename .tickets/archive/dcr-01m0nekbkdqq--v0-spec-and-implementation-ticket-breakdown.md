---
id: dcr-01m0nekbkdqq
title: v0 spec and implementation ticket breakdown
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.749301225Z'
updated: '2026-08-23T20:52:40.807811141Z'
closed: '2026-08-23T20:52:40.807811141Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
deps:
- dcr-01m0nekb5z5c
- dcr-01m0nekb8ks4
- dcr-01m0nekbb7zp
- dcr-01m0nekbdy5m
- dcr-01m0nekbgpk7
- dcr-01m0nspa8aee
- dcr-01m0p4k0awfp
- dcr-01m0p812gcw2
- dcr-01m0qyda4jnd
---

## Description

## Question

Assemble the spec from the resolved tickets and ADRs, and cut it into implementation tickets for a build effort: package skeleton, record & persistence, diff review buffer, plain-file review, export, commands & keymap, tests. This is the last ticket on the map; closing it means the way is clear.

## Notes

**2026-08-23T20:52:40.807811141Z**

Spec assembled and cut. The spec lives in knot as the build epic 'revu v0 build' (dcr-01m0r63dzcq8): problem/solution, 38 user stories, ADR-0001..0011 index as the implementation decisions, testing seams (primary: command layer driven by ERT over a fixture git repo, asserting on the Sidecar JSON and the rendered buffer; secondary: the anchoring engine as a pure function), out-of-scope, and the agent contract. Ten afk implementation tickets created as its children, wired with native deps and core-first priorities (p1: skeleton+harness -> record & Sidecar persistence -> anchoring engine / diff render -> annotation commands -> revdiff Export; p2: reviewed-tracking -> plain-file review, reload/round-trip, and last the keymap/evil/transient ticket gated on all four). Tests land per ticket, no trailing test ticket; harness and fixture builder live in the skeleton ticket. This was the last ticket on the map: the way is clear.
