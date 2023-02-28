# -*- coding:binary; frozen_string_literal: true -*-

module ZIMG
  module JPEG
    module IDCT
      FIX_0_298631336 =  2446 # FIX(0.298631336)
      FIX_0_390180644 =  3196 # FIX(0.390180644)
      FIX_0_541196100 =  4433 # FIX(0.541196100)
      FIX_0_765366865 =  6270 # FIX(0.765366865)
      FIX_0_899976223 =  7373 # FIX(0.899976223)
      FIX_1_175875602 =  9633 # FIX(1.175875602)
      FIX_1_501321110 = 12299 # FIX(1.501321110)
      FIX_1_847759065 = 15137 # FIX(1.847759065)
      FIX_1_961570560 = 16069 # FIX(1.961570560)
      FIX_2_053119869 = 16819 # FIX(2.053119869)
      FIX_2_562915447 = 20995 # FIX(2.562915447)
      FIX_3_072711026 = 25172 # FIX(3.072711026)

      DCTSIZE       = 8
      CONST_BITS    = 13
      PASS1_BITS    = 2
      CENTERJSAMPLE = 128
      RANGE_BITS    = 2
      RANGE_CENTER  = CENTERJSAMPLE << RANGE_BITS
      RANGE_SUBSET  = RANGE_CENTER - CENTERJSAMPLE

      def RIGHT_SHIFT(a, b)
        a >> b
      end

      def DEQUANTIZE(a, b)
        a * b
      end

      def range_limit(sample)
        sample -= RANGE_SUBSET
        if sample < 0
          0
        else
          (sample > 0xFF ? 0xFF : sample)
        end.chr
      end

      def jpeg_idct_islow(data_in, data_out, workspace, output_col: 0)
        inptr = 0
        quantptr = 0
        wsptr = 0

        #        printf("[d] in: ")
        #        64.times do |i|
        #            printf("%d ", data_in[i])
        #        end
        #        printf("\n")

        DCTSIZE.times do
          # Due to quantization, we will usually find that many of the input
          # coefficients are zero, especially the AC terms.  We can exploit this
          # by short-circuiting the IDCT calculation for any column in which all
          # the AC terms are zero.  In that case each output is equal to the
          # DC coefficient (with scale factor as needed).
          # With typical images and quantization tables, half or more of the
          # column DCT calculations can be simplified this way.

          if data_in[inptr + DCTSIZE * 1] == 0 && data_in[inptr + DCTSIZE * 2] == 0 && data_in[inptr + DCTSIZE * 3] == 0 &&
             data_in[inptr + DCTSIZE * 4] == 0 && data_in[inptr + DCTSIZE * 5] == 0 && data_in[inptr + DCTSIZE * 6] == 0 &&
             data_in[inptr + DCTSIZE * 7] == 0
            # AC terms all zero
            dcval = DEQUANTIZE(data_in[inptr], qtable[quantptr]) << PASS1_BITS
            # printf "[d] dcval = %d, data_in:%d, qtable:%d\n", dcval, data_in[inptr], qtable[quantptr]

            workspace[wsptr + DCTSIZE * 0] = dcval
            workspace[wsptr + DCTSIZE * 1] = dcval
            workspace[wsptr + DCTSIZE * 2] = dcval
            workspace[wsptr + DCTSIZE * 3] = dcval
            workspace[wsptr + DCTSIZE * 4] = dcval
            workspace[wsptr + DCTSIZE * 5] = dcval
            workspace[wsptr + DCTSIZE * 6] = dcval
            workspace[wsptr + DCTSIZE * 7] = dcval

            inptr += 1 # advance pointers to next column
            quantptr += 1
            wsptr += 1
            next
          end

          # Even part: reverse the even part of the forward DCT.
          # The rotator is c(-6).

          z2 = DEQUANTIZE(data_in[inptr + DCTSIZE * 0], qtable[quantptr])
          z3 = DEQUANTIZE(data_in[inptr + DCTSIZE * 4], qtable[quantptr + DCTSIZE * 4])
          z2 <<= CONST_BITS
          z3 <<= CONST_BITS
          # Add fudge factor here for final descale.
          z2 += 1 << (CONST_BITS - PASS1_BITS - 1)

          tmp0 = z2 + z3
          tmp1 = z2 - z3

          z2 = DEQUANTIZE(data_in[inptr + DCTSIZE * 2], qtable[quantptr + DCTSIZE * 2])
          z3 = DEQUANTIZE(data_in[inptr + DCTSIZE * 6], qtable[quantptr + DCTSIZE * 6])

          z1 = (z2 + z3) * FIX_0_541196100 # c6
          tmp2 = z1 + z2 * FIX_0_765366865 # c2-c6
          tmp3 = z1 - z3 * FIX_1_847759065 # c2+c6

          tmp10 = tmp0 + tmp2
          tmp13 = tmp0 - tmp2
          tmp11 = tmp1 + tmp3
          tmp12 = tmp1 - tmp3

          # Odd part per figure 8; the matrix is unitary and hence its
          # transpose is its inverse.  i0..i3 are y7,y5,y3,y1 respectively.

          tmp0 = DEQUANTIZE(data_in[inptr + DCTSIZE * 7], qtable[quantptr + DCTSIZE * 7])
          tmp1 = DEQUANTIZE(data_in[inptr + DCTSIZE * 5], qtable[quantptr + DCTSIZE * 5])
          tmp2 = DEQUANTIZE(data_in[inptr + DCTSIZE * 3], qtable[quantptr + DCTSIZE * 3])
          tmp3 = DEQUANTIZE(data_in[inptr + DCTSIZE * 1], qtable[quantptr + DCTSIZE * 1])

          z2 = tmp0 + tmp2
          z3 = tmp1 + tmp3

          z1 = (z2 + z3) * FIX_1_175875602       #  c3
          z2 *= - FIX_1_961570560                # -c3-c5
          z3 *= - FIX_0_390180644                # -c3+c5
          z2 += z1
          z3 += z1

          z1 = (tmp0 + tmp3) * - FIX_0_899976223 # -c3+c7
          tmp0 *= FIX_0_298631336                # -c1+c3+c5-c7
          tmp3 *= FIX_1_501321110                #  c1+c3-c5-c7
          tmp0 += z1 + z2
          tmp3 += z1 + z3

          z1 = (tmp1 + tmp2) * - FIX_2_562915447 # -c1-c3
          tmp1 *= FIX_2_053119869                #  c1+c3-c5+c7
          tmp2 *= FIX_3_072711026                #  c1+c3+c5-c7
          tmp1 += z1 + z3
          tmp2 += z1 + z2

          # Final output stage: inputs are tmp10..tmp13, tmp0..tmp3

          workspace[wsptr + DCTSIZE * 0] =  RIGHT_SHIFT(tmp10 + tmp3, CONST_BITS - PASS1_BITS)
          workspace[wsptr + DCTSIZE * 7] =  RIGHT_SHIFT(tmp10 - tmp3, CONST_BITS - PASS1_BITS)
          workspace[wsptr + DCTSIZE * 1] =  RIGHT_SHIFT(tmp11 + tmp2, CONST_BITS - PASS1_BITS)
          workspace[wsptr + DCTSIZE * 6] =  RIGHT_SHIFT(tmp11 - tmp2, CONST_BITS - PASS1_BITS)
          workspace[wsptr + DCTSIZE * 2] =  RIGHT_SHIFT(tmp12 + tmp1, CONST_BITS - PASS1_BITS)
          workspace[wsptr + DCTSIZE * 5] =  RIGHT_SHIFT(tmp12 - tmp1, CONST_BITS - PASS1_BITS)
          workspace[wsptr + DCTSIZE * 3] =  RIGHT_SHIFT(tmp13 + tmp0, CONST_BITS - PASS1_BITS)
          workspace[wsptr + DCTSIZE * 4] =  RIGHT_SHIFT(tmp13 - tmp0, CONST_BITS - PASS1_BITS)

          inptr += 1 # advance pointers to next column
          quantptr += 1
          wsptr += 1
        end

        # Pass 2: process rows from work array, store into output array.
        # Note that we must descale the results by a factor of 8 == 2**3,
        # and also undo the PASS1_BITS scaling.

        wsptr = 0
        DCTSIZE.times do |ctr|
          outptr = ctr * DCTSIZE + output_col

          # Add range center and fudge factor for final descale and range-limit.
          z2 = workspace[wsptr + 0] + (((RANGE_CENTER) << (PASS1_BITS + 3)) + (1 << (PASS1_BITS + 2)))

          # Rows of zeroes can be exploited in the same way as we did with columns.
          # However, the column calculation has created many nonzero AC terms, so
          # the simplification applies less often (typically 5% to 10% of the time).
          # On machines with very fast multiplication, it's possible that the
          # test takes more time than it's worth.  In that case this section
          # may be commented out.

          if workspace[wsptr + 1] == 0 && workspace[wsptr + 2] == 0 && workspace[wsptr + 3] == 0 && workspace[wsptr + 4] == 0 &&
             workspace[wsptr + 5] == 0 && workspace[wsptr + 6] == 0 && workspace[wsptr + 7] == 0
            # AC terms all zero
            dcval = range_limit(RIGHT_SHIFT(z2, PASS1_BITS + 3))

            data_out[outptr + 0] = dcval
            data_out[outptr + 1] = dcval
            data_out[outptr + 2] = dcval
            data_out[outptr + 3] = dcval
            data_out[outptr + 4] = dcval
            data_out[outptr + 5] = dcval
            data_out[outptr + 6] = dcval
            data_out[outptr + 7] = dcval

            wsptr += DCTSIZE # advance pointer to next row
            next
          end

          # Even part: reverse the even part of the forward DCT.
          # The rotator is c(-6).

          z3 = workspace[wsptr + 4]

          tmp0 = (z2 + z3) << CONST_BITS
          tmp1 = (z2 - z3) << CONST_BITS

          z2 =  workspace[wsptr + 2]
          z3 =  workspace[wsptr + 6]

          z1 = (z2 + z3) * FIX_0_541196100 # c6
          tmp2 = z1 + z2 * FIX_0_765366865 # c2-c6
          tmp3 = z1 - z3 * FIX_1_847759065 # c2+c6

          tmp10 = tmp0 + tmp2
          tmp13 = tmp0 - tmp2
          tmp11 = tmp1 + tmp3
          tmp12 = tmp1 - tmp3

          # Odd part per figure 8; the matrix is unitary and hence its
          # transpose is its inverse.  i0..i3 are y7,y5,y3,y1 respectively.

          tmp0 =  workspace[wsptr + 7]
          tmp1 =  workspace[wsptr + 5]
          tmp2 =  workspace[wsptr + 3]
          tmp3 =  workspace[wsptr + 1]

          z2 = tmp0 + tmp2
          z3 = tmp1 + tmp3

          z1 = (z2 + z3) * FIX_1_175875602       #  c3
          z2 *= - FIX_1_961570560                # -c3-c5
          z3 *= - FIX_0_390180644                # -c3+c5
          z2 += z1
          z3 += z1

          z1 = (tmp0 + tmp3) * - FIX_0_899976223 # -c3+c7
          tmp0 *= FIX_0_298631336                # -c1+c3+c5-c7
          tmp3 *= FIX_1_501321110                #  c1+c3-c5-c7
          tmp0 += z1 + z2
          tmp3 += z1 + z3

          z1 = (tmp1 + tmp2) * - FIX_2_562915447 # -c1-c3
          tmp1 *= FIX_2_053119869                #  c1+c3-c5+c7
          tmp2 *= FIX_3_072711026                #  c1+c3+c5-c7
          tmp1 += z1 + z3
          tmp2 += z1 + z2

          # Final output stage: inputs are tmp10..tmp13, tmp0..tmp3

          data_out[outptr + 0] = range_limit(RIGHT_SHIFT(tmp10 + tmp3, CONST_BITS + PASS1_BITS + 3))
          data_out[outptr + 7] = range_limit(RIGHT_SHIFT(tmp10 - tmp3, CONST_BITS + PASS1_BITS + 3))
          data_out[outptr + 1] = range_limit(RIGHT_SHIFT(tmp11 + tmp2, CONST_BITS + PASS1_BITS + 3))
          data_out[outptr + 6] = range_limit(RIGHT_SHIFT(tmp11 - tmp2, CONST_BITS + PASS1_BITS + 3))
          data_out[outptr + 2] = range_limit(RIGHT_SHIFT(tmp12 + tmp1, CONST_BITS + PASS1_BITS + 3))
          data_out[outptr + 5] = range_limit(RIGHT_SHIFT(tmp12 - tmp1, CONST_BITS + PASS1_BITS + 3))
          data_out[outptr + 3] = range_limit(RIGHT_SHIFT(tmp13 + tmp0, CONST_BITS + PASS1_BITS + 3))
          data_out[outptr + 4] = range_limit(RIGHT_SHIFT(tmp13 - tmp0, CONST_BITS + PASS1_BITS + 3))

          wsptr += DCTSIZE # advance pointer to next row
        end
      end
    end
  end
end
