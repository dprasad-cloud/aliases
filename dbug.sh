pod_part = $2;
   con_part = $3;

   # If they easily fit under 33 chars with a ".*" middle separator
   if (length(pod_part) + length(con_part) + 2 <= 33) {
       display_name = pod_part ".*" con_part
   } else {
       # Only run the heavy truncation math if they actually overflow 33 chars
       p_len = length(pod_part)
       c_len = length(con_part)

       total_raw_len = p_len + c_len + 9
       overflow = total_raw_len - 33

       if (overflow > 0 && c_len > 10) {
           c_reduction = (c_len - 10 >= overflow) ? overflow : (c_len - 10)
           c_len = c_len - c_reduction
           overflow = overflow - c_reduction
       }

       if (overflow > 0 && c_len > 5) {
           c_reduction = (c_len - 5 >= overflow) ? overflow : (c_len - 5)
           c_len = c_len - c_reduction
       }

       p_end = (p_len >= 5) ? substr(pod_part, p_len - 4) : pod_part
       c_trim = substr(con_part, length(con_part) - c_len + 1)

       start_len = 33 - 2 - 5 - 2 - length(c_trim)
       if (start_len < 1) start_len = 1

       p_start = substr(pod_part, 1, start_len)
       display_name = p_start ".*" p_end ".*" c_trim
   }