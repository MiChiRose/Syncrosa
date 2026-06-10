# -*- coding: utf-8 -*-
from __future__ import absolute_import
import re
from core.network import call_ai_for_playlist

def generate_playlist_ids(provider, api_key, model, mood, count, library_sample):
    prompt = u"""You are an expert DJ AI.
Create a playlist from the provided library.
Event/Mood requested: {mood}
Target Track Count: {count}

Library format: PersistentID|Artist|Title|Genre|Year
{library}

CRITICAL RULES:
1. Select exactly {count} tracks. If you cannot find perfect matches, select the closest alternatives based on artist style or genre to ensure you reach the target count.
2. You MUST return ONLY the 16-character hexadecimal PersistentID for each selected track.
3. DO NOT return track titles or artist names. Only the IDs (the first part of each line).
4. Your ENTIRE output MUST BE ONLY a single, flat JSON array of these ID strings.
5. DO NOT add explanations, notes, or markdown.
CORRECT OUTPUT FORMAT: ["A1B2C3D4E5F67890", "0987654321ABCDEF"]
""".format(mood=mood, count=count, library=u"\\n".join(library_sample))
    
    ok, res = call_ai_for_playlist(provider, api_key, model, prompt)
    if not ok:
        return False, res
        
    try:
        extracted_ids = re.findall(r'([a-fA-F0-9]{16})', str(res))
        if not extracted_ids: 
            extracted_ids = re.findall(r'"([a-fA-F0-9]{10,20})"', str(res))
        
        if not extracted_ids:
            return False, "No valid IDs found in AI response."
            
        final_ids = []
        for tid in extracted_ids:
            if tid not in final_ids: 
                final_ids.append(tid)
        
        return True, final_ids[:int(count)]
    except Exception as e:
        return False, "Parsing Error: " + str(e)
