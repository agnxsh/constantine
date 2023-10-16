# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.
import 
 ./helper_types,
 ../../../constantine/math/config/[type_ff, curves],
 ../../../constantine/math/elliptic/[ec_twistededwards_projective, ec_twistededwards_batch_ops],
 ../../../constantine/math/arithmetic/[finite_fields],
 ../../../constantine/math/arithmetic

# ############################################################
#
#       Barycentric Form using Precompute Optimisation
#
# ############################################################

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g 

func newPrecomputedWeights* [PrecomputedWeights] (res: var PrecomputedWeights)=
 
 var midpoint: uint64 = 256-1
 for i in uint64(0)..<midpoint:
  var weights {.noInit.}: EC_P_Fr
  weights.computeBarycentricWeights(i) 

  var inverseWeights {.noInit.}: EC_P_Fr
  inverseWeights.inv(weights)

  res.barycentricWeights[i] = weights
  res.barycentricWeights[i+midpoint] = inverseWeights

  midpoint = uint64(DOMAIN) - 1

  for i in uint64(1)..<uint64(DOMAIN):
   var k {.noInit.}: EC_P_Fr
   var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
   i_bg.setUint(uint64(i))
   k.fromBig(i_bg)

   k.inv(k)


   var neg_k : EC_P_Fr
   var zero : EC_P_Fr
   zero.setZero()
   neg_k.diff(zero, k)
   res.invertedDomain[i-1] = k
   res.invertedDomain[(i-1) + midpoint] = neg_k


func computeBarycentricWeights* [EC_P_Fr] (res: var EC_P_Fr, element : uint64) = 
 if element <= uint64(DOMAIN):

  var domain_element_Fr: EC_P_Fr
  var bigndom : matchingOrderBigInt(Banderwagon)
  bigndom.setUint(uint64(element))
  domain_element_Fr.fromBig(bigndom)

  res.setOne()

  for i in uint64(0)..<uint64(DOMAIN):
    if i==element:
      continue

    var i_Fr: EC_P_Fr 

    var bigi:  matchingOrderBigInt(Banderwagon)
    bigi.setUint(uint64(i))
    i_Fr.fromBig(bigi)
  
    var temp: EC_P_Fr
    temp.diff(domain_element_Fr,i_Fr)
    res.prod(res, temp)
  

# func BatchInversion(points : seq[EC_P_Fr]) : seq[EC_P_Fr] =
#  var result : array[len(points),EC_P_Fr]



func computeBarycentricCoefficients* [EC_P_Fr]( res: var openArray[EC_P_Fr], precomp: PrecomputedWeights, point : var EC_P_Fr) =

 for i in uint64(0)..<uint64(DOMAIN):
  var weight : EC_P_Fr
  weight = precomp.barycentricWeights[i]
  var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
  i_bg.setUint(uint64(i))
  var i_Fr {.noInit.} : EC_P_Fr
  i_Fr.fromBig(i_bg)
  
  res[i].diff(point, i_Fr)
  res[i].prod(res[i],weight)
 var totalProd : EC_P_Fr

 totalProd.setOne()

 for i in 0..<DOMAIN:
  var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
  i_bg.setUint(uint64(i))
  var i_Fr {.noInit.} : EC_P_Fr
  i_Fr.fromBig(i_bg)


  var tmp {.noInit.} : EC_P_Fr
  tmp.diff(point, i_Fr)

  totalProd.prod(totalProd, tmp)

  doAssert res.batchInvert(res) == true

  for i in uint64(0)..<uint64(DOMAIN):
    res[i].prod(res[i], totalProd)


func getInvertedElement* [EC_P_Fr] ( res: var EC_P_Fr, precomp : PrecomputedWeights, element : int, is_negative: bool) =
  var index = element -1 

  doAssert is_negative == true, "Index is negative!"

  var midpoint = len(precomp.invertedDomain) / 2
  index = index + midpoint
  
  res = precomp.invertedDomain[index]

func getWeightRatios* [EC_P_Fr] (result: var EC_P_Fr, precomp: PrecomputedWeights, numerator: var int, denominator: var int)=

  var a = precomp.barycentricWeights[numerator]
  var midpoint = len(precomp.barycentricWeights) / 2

  var b = precomp.barycentricWeights[denominator + midpoint]

  result.prod(a, b)



func getBarycentricInverseWeight* [EC_P_Fr] (res: var EC_P_Fr, precomp: PrecomputedWeights, i: int) =
  var midpoint = uint64(256)
  res = precomp.barycentricWeights[i+midpoint]

func absIntChecker*[int] (res: var int, x : int) =
  var is_negative {.noInit.}: bool
  if x < 0:
    is_negative = true

  if is_negative == true:
    res = -x



func divisionOnDomain* [EC_P_Fr](res: var array[DOMAIN,EC_P_Fr], precomp: PrecomputedWeights, index:  int, f:  openArray[EC_P_Fr])=
  var is_negative : bool = true
  var y = f[index]

  for i in uint64(0)..<DOMAIN:
   doAssert not(i == int(index))

   var denominator = i - int(index)
   var absDenominator {.noInit.}: int
   absDenominator.absIntChecker(denominator)

   doAssert absDenominator == denominator
   is_negative = false

   var denominatorInv = precomp.invertedDomain.getInvertedElement(absDenominator, is_negative)

   res[i].diff(f[i], y)
   res[i].prod(res[i], denominatorInv)


   var weight_ratios = precomp.getWeightRatios(int(index), i)

   var tmp {.noInit.}: EC_P_Fr
   tmp.prod(weight_ratios, res[i])

   res[index].diff(res[index], tmp)


