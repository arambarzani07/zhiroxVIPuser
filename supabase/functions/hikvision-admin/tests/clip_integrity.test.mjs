import { test } from 'node:test';
import assert from 'node:assert/strict';
import { duplicateWindow, summarizeClips } from '../clip_integrity.mjs';
const clip = (id, start, end, extra = {}) => ({ id, market_id:'market-a', channel_id:10, status:'ready', content_sha256:'same', clip_start_at:`2026-10-04T${start}Z`, clip_end_at:`2026-10-04T${end}Z`, ...extra });
test('identical files with disjoint windows warn; overlapping windows do not', () => {
 const a=clip('a','09:00:00','09:00:30');
 assert.equal(duplicateWindow(a,clip('b','09:01:00','09:01:30')),true);
 assert.equal(duplicateWindow(a,clip('b','09:00:15','09:00:45')),false);
 assert.equal(duplicateWindow(a,clip('b','09:00:30','09:01:00')),true);
});
test('different tenants, channels, hashes, failed clips and malformed windows never match',()=>{
 const a=clip('a','09:00:00','09:00:30');
 for(const extra of [{market_id:'market-b'},{channel_id:2},{content_sha256:'other'},{status:'failed'},{clip_start_at:null},{clip_end_at:'invalid'},{content_sha256:null},{id:'a'}]) {
  assert.equal(duplicateWindow(a,clip('b','09:01:00','09:01:30',extra)),false);
 }
});
test('summary counts clips once and uses latest clip build without inferring active version',()=>{
 const rows=[clip('a','09:02:00','09:02:30',{playback_metadata:{gateway_build:'time-window-3'},captured_at:'2026-10-04T09:03:00Z'}),clip('b','09:01:00','09:01:30'),clip('c','09:00:00','09:00:30')];
 assert.deepEqual(summarizeClips(rows),{sampled_clips:3,suspicious_clips:3,latest_clip_build:'time-window-3',latest_clip_captured_at:'2026-10-04T09:03:00Z'});
 assert.equal(summarizeClips([clip('d','09:00:00','09:00:30')]).latest_clip_build,null);
 assert.equal(summarizeClips([]).suspicious_clips,0);
});
