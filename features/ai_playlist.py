# -*- coding: utf-8 -*-
from __future__ import absolute_import
import re
from core.network import call_ai_for_playlist

def generate_playlist_ids(provider, api_key, model, mood, count, library_sample):
    MAX_CHUNK_SIZE = 500
    all_final_ids = []
    target_count = int(count)
    total_tracks = len(library_sample)
    
    # Calculate balanced chunks
    if total_tracks > MAX_CHUNK_SIZE:
        # Determine number of chunks (ceiling division)
        num_chunks = (total_tracks + MAX_CHUNK_SIZE - 1) // MAX_CHUNK_SIZE
        # Determine balanced size for each chunk (ceiling division)
        actual_chunk_size = (total_tracks + num_chunks - 1) // num_chunks
    else:
        num_chunks = 1
        actual_chunk_size = total_tracks

    # Split library into balanced parts
    chunks = [library_sample[i:i + actual_chunk_size] for i in range(0, total_tracks, actual_chunk_size)]
    # Ensure we didn't end up with an empty chunk at the end due to math rounding
    chunks = [c for c in chunks if c]
    num_chunks = len(chunks)
    
    print("\n[AI Playlist Optimization: Balanced Chunking]")
    print("Library size: {} tracks. Splitting into {} balanced chunks (max {} tracks each).".format(total_tracks, num_chunks, actual_chunk_size))
    
    for idx, chunk in enumerate(chunks):
        # Calculate how many tracks to ask from this chunk
        # Distribute the total count proportionally
        chunk_target = (target_count // num_chunks) + (1 if idx < (target_count % num_chunks) else 0)
        if chunk_target < 1: chunk_target = 1
        
        print("\n--- Processing Chunk {}/{} ({} tracks) ---".format(idx + 1, num_chunks, len(chunk)))
        
        prompt = u"""You are an expert DJ AI.
Create a playlist from the provided library sample.
Event/Mood requested: {mood}
Target Track Count for this sample: {chunk_count}

Library format: PersistentID|Artist|Title|Genre|Year
{library}

CRITICAL RULES:
1. Select UP TO {chunk_count} tracks from THIS sample that best match the requested mood. If you cannot find exactly {chunk_count} tracks, it is OK to return fewer. Just do not exceed {chunk_count}.
2. Be creative and broad in your interpretation of the mood. Do not get stuck on specific keywords.
3. You MUST return ONLY the 16-character hexadecimal PersistentID for each selected track. 
4. DO NOT convert the PersistentID to decimal. DO NOT change its case. Copy it EXACTLY as it appears.
5. Your ENTIRE output MUST BE ONLY a single, flat JSON array of these ID strings.
6. DO NOT add explanations, notes, or markdown.
""".format(mood=mood, chunk_count=chunk_target, library=u"\\n".join(chunk))

        ok, res = call_ai_for_playlist(provider, api_key, model, prompt)
        if not ok:
            print("Warning: Chunk {} failed: {}".format(idx + 1, res))
            continue 
            
        try:
            # Extract IDs in order they appear in response
            extracted_ids = re.findall(r'([a-fA-F0-9]{16})', str(res))
            if not extracted_ids: 
                extracted_ids = re.findall(r'"([a-fA-F0-9]{10,20})"', str(res))
            
            if not extracted_ids:
                print("Warning: Chunk {} returned 0 valid IDs or misunderstood the format. Skipping to next chunk...".format(idx + 1))
                continue

            # Add new unique IDs to the main list while preserving order
            for tid in extracted_ids:
                if tid not in all_final_ids:
                    all_final_ids.append(tid)
                    
            print("Chunk {} provided {} valid track IDs.".format(idx + 1, len(extracted_ids)))
        except Exception as e:
            print("Error parsing chunk {}: {}".format(idx + 1, str(e)))

    if not all_final_ids:
        return False, "No valid IDs found in any of the chunks."
        
    print("\nOptimization Complete. Total tracks gathered: {}".format(len(all_final_ids)))
    
    # Strictly take from the beginning (first results) up to the target count
    final_list = all_final_ids[:target_count]
    print("Final playlist will contain {} tracks (trimmed if needed).".format(len(final_list)))
    
    return True, final_list

