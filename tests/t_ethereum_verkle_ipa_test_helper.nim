# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
  ../constantine/eth_verkle_ipa/[multiproof, barycentric_form, eth_verkle_constants],
  ../constantine/math/config/[type_ff, curves],
  ../constantine/math/elliptic/[
    ec_twistededwards_affine,
    ec_twistededwards_projective
  ],
  ../constantine/serialization/[
    codecs_status_codes,
    codecs_banderwagon,
    codecs
  ],
  ../constantine/math/arithmetic

# ############################################################
#
#       All the helper functions required for testing
#
# ############################################################

func ipaEvaluate* [Fr] (res: var Fr, poly: openArray[Fr], point: Fr,  n: static int) = 
  var powers {.noInit.}: array[n,Fr]
  powers.computePowersOfElem(point, poly.len)

  res.setZero()

  for i in 0 ..< poly.len:
    var tmp: Fr
    tmp.prod(powers[i], poly[i])
    res.sum(res,tmp)

  res.setZero()

  for i in 0 ..< poly.len:
    var tmp {.noInit.}: Fr
    tmp.prod(powers[i], poly[i])
    res.sum(res,tmp)

func truncate* [Fr] (res: var openArray[Fr], s: openArray[Fr], to: int, n: static int)=
  for i in 0 ..< to:
    res[i] = s[i]

func interpolate* [Fr] (res: var openArray[Fr], points: openArray[Coord], n: static int) =
    
  var one : Fr
  one.setOne()

  var zero  : Fr
  zero.setZero()

  var max_degree_plus_one = points.len

  doAssert (max_degree_plus_one >= 2).bool() == true, "Should be interpolating for degree >= 1!"

  for k in 0 ..< points.len:
    var point: Coord
    point = points[k]

    var x_k : Fr 
    x_k = point.x
    var y_k  : Fr 
    y_k = point.y

    var contribution : array[n,Fr]
    var denominator : Fr
    denominator.setOne()

    var max_contribution_degree : int= 0

    for j in 0 ..< points.len:
      var point : Coord 
      point = points[j]
      var x_j : Fr 
      x_j = point.x

      if j != k:
        var differ = x_k
        differ.diff(differ, x_j)

        denominator.prod(denominator,differ)

        if max_contribution_degree == 0:

          max_contribution_degree = 1
          contribution[0].diff(contribution[0],x_j)
          contribution[1].sum(contribution[1],one)

        else:

          var mul_by_minus_x_j : array[n,Fr]
          for el in 0 ..< contribution.len:
            var tmp : Fr = contribution[el]
            tmp.prod(tmp,x_j)
            tmp.diff(zero,tmp)
            mul_by_minus_x_j[el] = tmp

          for i in 1 ..< contribution.len:
            contribution[i] = contribution[i-1]
                    
          contribution[0] = zero
          # contribution.truncate(contribution, max_degree_plus_one, n)

          doAssert max_degree_plus_one == mul_by_minus_x_j.len == true, "Malformed mul_by_minus_x_j!"

          for i in 0 ..< contribution.len:
            var other = mul_by_minus_x_j[i]
            contribution[i].sum(contribution[i],other) 
            
    denominator.inv(denominator)
    doAssert not(denominator.isZero().bool()) == true, "Denominator should not be zero!"

    for i in 0 ..< contribution.len:
      var tmp : Fr 
      tmp = contribution[i]
      tmp.prod(tmp,denominator)
      tmp.prod(tmp,y_k)
      res[i].sum(res[i], tmp)

        
#Initiating evaluation points z in the FiniteField (253)
func setEval* [Fr] (res: var Fr, x : Fr)=

  var tmp_a {.noInit.} : Fr

  var one {.noInit.}: Fr
  one.setOne()

  tmp_a.diff(x, one)

  var tmp_b : Fr
  tmp_b.sum(x, one)

  var tmp_c : Fr = one

  for i in 0 ..< 253:
    tmp_c.prod(tmp_c,x) 

  res.prod(tmp_a, tmp_b)
  res.prod(res,tmp_c)

#Evaluating the point z outside of VerkleDomain, here the VerkleDomain is 0-256, whereas the FieldSize is
#everywhere outside of it which is upto a 253 bit number, or 2²⁵³.
func evalOutsideDomain* [Fr] (res: var Fr, precomp: PrecomputedWeights, f: openArray[Fr], point: Fr)=

  var pointMinusDomain: array[VerkleDomain, Fr]
  for i in 0 ..< VerkleDomain:

    var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
    i_bg.setUint(uint64(i))
    var i_fr {.noInit.} : Fr
    i_fr.fromBig(i_bg)

    pointMinusDomain[i].diff(point, i_fr)
    pointMinusDomain[i].inv(pointMinusDomain[i])

  var summand: Fr
  summand.setZero()

  for x_i in 0 ..< pointMinusDomain.len:
    var weight: Fr
    weight.getBarycentricInverseWeight(precomp,x_i)
    var term: Fr
    term.prod(weight, f[x_i])
    term.prod(term, pointMinusDomain[x_i])

    summand.sum(summand,term)

  res.setOne()

  for i in 0 ..< VerkleDomain:

    var i_bg: matchingOrderBigInt(Banderwagon)
    i_bg.setUint(uint64(i))
    var i_fr : Fr
    i_fr.fromBig(i_bg)

    var tmp : Fr
    tmp.diff(point, i_fr)
    res.prod(res, tmp)

  res.prod(res,summand)


func testPoly256* [Fr] (res: var openArray[Fr], polynomialUint: openArray[uint64])=

  var n = polynomialUint.len
  doAssert (polynomialUint.len <= 256) == true, "Cannot exceed 256 coeffs!"

  for i in 0 ..< n:
    var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
    i_bg.setUint(uint64(polynomialUint[i]))
    res[i].fromBig(i_bg)
  
  var pad = 256 - n
  for i in n ..< pad:
    res[i].setZero()

func isPointEqHex*(point: EC_P, expected: string): bool {.discardable.} =

  var point_bytes {.noInit.} : Bytes
  if point_bytes.serialize(point) == cttCodecEcc_Success:
    doAssert (point_bytes.toHex() == expected).bool() == true, "Point does not equal to the expected hex value!"

func isScalarEqHex*(scalar: matchingOrderBigInt(Banderwagon), expected: string) : bool {.discardable.} =

  var scalar_bytes {.noInit.} : Bytes
  if scalar_bytes.serialize_scalar(scalar) == cttCodecScalar_Success:
    doAssert (scalar_bytes.toHex() == expected).bool() == true, "Scalar does not equal to the expected hex value!"

func getDegreeOfPoly*(res: var int, p: openArray[Fr]) = 
  for d in countdown(p.len - 1, 0):
    if not(p[d].isZero().bool()):
      res = d
    
    else:
      res = -1

###################################################################
##
##
##    Test Vectors for Computing the correct Pedersen Commitment
##
##
###################################################################

const testScalarsHex* : array[256, string] = [
 "0x4995e0394bfbb0d9f0e03cc3bace2e59a2586f489366de73a619c3065d1f453",
"0xf8a70e52fd135f1058cd7b053c05d1ea9dc11733a5a08e6ac935ed177544e1",
"0x14b09527f6383df9c8905c7889bcbeba87b657be65601839a5332fbde0ddc550",
"0x1f81dfa6954347cc351e7364edc5b7199dc5ee6a22b65d90a7f4f94b22c818c",
"0x1727deb4220cca5b35560c3955a3fad355449fa584ce42920041d347ee23fca",
"0x16cb5f9aba8ecf9f77f06a8d06c64285b84d6b5559d77616a0bab973ad4964cd",
"0x183847b1ae9e29bb90c654741d405a80850d1ff631ebb245f666f7d1ca4d65c",
"0x11b81ae0766a93fee2e6ab4ca0623d8274144bd603bd811972ffc24c826e44e3",
"0x1c59f8d890d7a5a2bd73effc8279f7e34887f34b8ccc8ce8fa4a580a1ce61132",
"0x1317b45e57588d01c5fd436a60a04abc337a280f25d23ab37df6b9156dee5d85",
"0xb9974a3a6645049cf1cf183b361a6988fbf6c0a0f9a708f8bb201f54e002519",
"0x17e0ec9f483356fd2130e3b3ed3db4bac83cd7de5f89335106d288997cc8e3b2",
"0x6dae8d46c830d92d0353c5c8d61981f99ecce734a9f3391a5bea0f2aed44ba8",
"0x11361ae0d625acf238ae24d59db4cc2e00a2f33f1bcc981466466ecb20628321",
"0x9683098c13fc42a4b3c5944e5ba7145d740c23a03b93bd9f936514900426571",
"0x1755c891cd5a2403b9a91ef385fc5c7d312b2eb5e8d55928ab5a0df1442564f4",
"0xc56a270ef8d966af4f10affb76b36e9d40733693e22cd2da9e2ef49fa67d4d8",
"0xeba6b2793ec22614fdedce7f437573d53f4c6efb30869fe4e71b063c6727a1e",
"0x18bd4101e6affd1a5b3a282d3a85d2337a52bd13eae00cc2113fb4bf0f11c823",
"0xb854820f631da4e25ba5ce04f529726916f0526680d9d4e5aecdeec216f3db9",
"0x1b3061ae584158fada2f476514f207c43ee833059bcce26e21be43e79a2a24bf",
"0x1bc4abe78479be2537e8d1311bb565b13d6480d8c958e7fbc8c06bd47368e60b",
"0x1c3261eb7c7f27d9480bc8ced267c94ef6759fdc623e4e0aa4c81a7232f0a03e",
"0x4ab1c66bd81aa384173c63bf75b8a3bfb9ae8f5b471d45c2384422b6990ca3a",
"0xdbd48217b1b7f8493fbf96525c5b2a55fcd1a130855f629619042040800f109",
"0x22c407159a9d992538180f919814a7a219e1990dd908d131fe93eafe4aee586",
"0xa3fea0fd12a4fffe63a121330599c077992c78a4e4882450bef9f41d5d42f23",
"0x17d76bdfc265ad4b8a63b2a973bac1533f2f1c8dc9e935d08fe6414c7196eaf2",
"0xe277b1012064a36f33980b57a6391feedc2353d99b33ba6994166e671c7267a",
"0x17ec781e2491753b882bca53be06f755375b78966f7a89a59db31fc1cc4d6b90",
"0x1cb2b9e55379d4ae757a57e13ae8093e9c8ae05f070ebb47f6d986ae480deae4",
"0x29f8064eafa340ff5104ae09a1c505a63d9398115e8122faeff55cf89742704",
"0x1b0c3644670c237c8da70b070c36e8fcfaafafcc885d0eb315c9feb390628c0c",
"0xedfaaf800031e209d92ff6b4389f5b8420ce832e7a276f167f1c9408c978357",
"0xb54f8923e3d29d3adeba8e37d5e63bd16f152024f83f82e341fd97aad1810ca",
"0xd6b2cb8319395eeecb085b7bdfd7e61689d61471ccdbfed302673571db35d83",
"0x14aba65ebf2152c9fecb918c50945f7a7421bf7bb0a0ec0ed3b098c679e48a7b",
"0x417c01e1c0b6afc2d4e3e13a4d777c2e76d4ac86c9c3824b90595d91858d4da",
"0x5285218581aba02726231b651bc9db3c03c50bf719e70b894c7b5b6b334b8b5",
"0xc7ffa802761810e0a796cdf40bd0b568fb7972e9d63139a803c801f7260ebb5",
"0x1c6129fa9ab858e9eb550ffeb8b4a4eb2ecf9b6927db23ea80170f226f2c38bb",
"0x95d36da1c8113c5a79c17f7b71616a224a0e6f88cbc86ee9ad8460c901baa43",
"0x12ec2deadb0c4db15fe112123b8bfd80c06cdfe1364c3fe36604eee671ca502c",
"0x17d1c7f5117e47e1c3014d139c7ca6d7178db7aa193f274905e2084de5b468a9",
"0x17d56469372259139e9b9b3326288aa86d8230046a76de75095422201db964df",
"0xd820def32d01b9c5865485048ee5a7e7e91caabc015807d3bb28161d4fc7132",
"0x1c21d5effac3657fac0eb763fdb3ecca68b167cf1834e67230a39cf446851136",
"0x196ab3c5fe7cc032f2437a0aa79c8274de32b70abc9877ebab58a043ce3403ed",
"0xe6c6b87dffd25742c58be147e2f79d663da6f95f9c9d20838cc7cbf2852a96",
"0x15d776ed4919653ad1e2d72e15b8de26515cac87087720232c439a20a732e571",
"0x90833cfacb9987a0a4a106b49fe665ebe2603edff75487bb0bc9fad9a97900b",
"0x5f0cd5dd02562e963624408bd0a8b7298078ebcee53795ad1e7f128724b8181",
"0x639909eb231a128467b54a9425c2e5120805f5cc6efc096827bccb5faa904eb",
"0x191bd9e4f5f009ba2ee24e9d66ec8a5dfb2a93a9e473dc4f0275c48c39f0b18a",
"0x16fab78b28964c7724392874782daba9d16520ffe7cd5fe4a4524712d78eb9e5",
"0x19f54f8186cd6d66e55dad5d8b76d039e609ee6b6ee6ef5507f3d39b5637b057",
"0x1264517cfa7ec0c4916cd5645e17bd4497856de5fcbd7a12478536c720a6f56",
"0x348e42b4c763799a48b7065ae87eb7afc44e93ccc370b9b165d2e7947ff3599",
"0x4674ad5abc5aa597cbeae4504b7a428482ba68a700e7af7fef91c91c895b223",
"0xb0481de6e636c1fc4a422508953fba2e4b5caedf1b5d78b7ef5e7597a32225f",
"0x908969895a8507358c67e5d95798f3bc547535db9cd467af9a98f5625c7df06",
"0x49487a59c6d1ccf721c34a19292a50ffbc93a13fa015d91b0cb8f27c91783f3",
"0x15c36da608f72ba20e8c7f921316853c15aeb90df148f6bb0cdb190ecafdafb6",
"0x168aefa18d2bd1b0f1ea4753722623b40c36e1c361fdecd58f39c37911d4d06f",
"0x1040ba954de137232db73046cbe6eb2f869750500273abbc2e5f7e6ac74430b4",
"0x897646c891d862d48a217de7487ce14bd14a6590abed2304de9335314a99aed",
"0x19007bcbf092296751f6463024fc72424288d37a5b7ac274cd49de80e600c873",
"0x7cf39d72f54b0e1c6ca5b46a52b38f743730af9a71818c63bcc96c93ea44a9",
"0x18b09f6e7f42d5188f1d83f78a7fc983130bb2d80411bf929671407b0e3783d8",
"0xec43992580f0020e964e0589f68e3227d4a96d64c95da534d81a651e0905c72",
"0xa9970f6b1fe44499109ddd2d9328c457365fe9f34504c1aa9d44fdccef97d3d",
"0x7317891c5f3afcc459fe58a90d0eab0a24ba41122237e21c2afb7216b23591d",
"0x1a8ec4f5968f2efbf772fe4bc8c7aec013673c8c8aeb730377685abffbd52968",
"0xa528305415093752023d917f2a49200e5b5a4064855506af54556347e14db64",
"0x182c40b3ec856ced2c6c34ca47db5fdd86031704fe6dc6169b52d29f29c05d88",
"0x8e1f8e591b665bb510940f945cf3a4c8802bb9dae6cb18b4fdd1d12097bcac9",
"0xfa7f23bf27e0651b9d33be9675623c191490453abf400b03cca74ef6b3483",
"0x6b8a6564f22fb3adcb44b0bf525e5757a3d9a1f6e763c100cc0ed81c6669224",
"0x13a98fb78e6107ddc1a99cb9183e3d4ec00a14c6ca46e765f860839aab7ae211",
"0x162bc0ecb2212327f207a7cbbd1252de16c9b9a94d526d486594b65e3ed5c1f9",
"0x4d101c0f739025602b2c85302c399ecd0bde14f90ee48918c2e96a9d496eb8e",
"0x10f3a9bb07c9209cd62fbaedc4ee53a6ada7a0ae338880cecf984dbb578d0e6",
"0x131764731443bf6a0a188d6295d372e4d578e94a0065b67e383ffa1546a8abdf",
"0xac85bd79e4396d4ef5b3bfe79ee039223784a8a6677e6ed486ca6157ecc1433",
"0x1711f3f0df5379dd5f480c0de52eeb2560932b1bdf60a05615664282888c9a9f",
"0x65a0b2fe0722c66ce2ffa13e7c8c3a29e640efdb63b3393bbe00896abddc404",
"0x2cf907ec61255710f898bee152b996111b15b5b965fcfdadc7cc992ee19eb50",
"0x582bcf0bc2df74064c44a76dd47ad524e300087bd18329d2f965fa1a1315396",
"0x11504d27c4c49544a9f8fdda6d48aba74ad4a2c275dcc7020cd904035bf60482",
"0x5f91f0824382f9c9129726e7faca317d8754976f3a3c1964eb0c1c3f74b0485",
"0x17fef014608f8d56c8f5c5667ab4f8da70454bc78fdb492766949f364f2a7f99",
"0xde9a1d7dba840eeeba44098710b2e7c807a099f8d4251372c577ec5d0757d3c",
"0x14adde0a412d3cb47ffc3cf68c7d1c7c89d012466cdff5efe200f37012851cf6",
"0xf79828757d6f916b126ae59ceb95e3bbd4c79b6f91ad315ae1e861e2f668d48",
"0x27f2787d39e07770bf250e30a839b709917cac33583951f015d3918657ecec5",
"0x1824f288244498100d6582c5654a7c465dd38ee7d9839b7a6b5e16ce9d913bd7",
"0x1736a9070c460ad15350eb409fba115169b8aa1350631f3f660d2655d2efd34d",
"0x152af1dce3cf66f9af8286db7c06d860ad1273dbce7aa6cf29228d8138757c5c",
"0x1cdb8c007f388b7048b67a37583ed41bdde80181c592bb69bda6c4ad104ca1de",
"0x606b3beb3528005b1a610d4cf5aae9b37d9ac107ac0bebc8db256ffac62ef41",
"0x110fcf4564b6005b4c1fb3669c92e5f01176a9cc6bfb2e34c267cfcbea52afa0",
"0x1939e7e6f7fa40becd0c1505e3e61b356f28ce9ec877742efdedfd2fdadf29f1",
"0x58be180bc4a2ebd188a35a07f891bfa42aaeba1de2ccd6d67f0c4100484ef72",
"0xb99415d3adccfbb848b7ba27b1f9fa895e57e0532d5457dc733fd4c40b9be86",
"0x9230654ea5ff89d2d7410422a40cc9b27c4de565a97ef9fd61c394022cf9b85",
"0x1a1a20e04a6dca9eb5eb11cb151ed60206752e66fb05e8bc2a80fa3c9857d722",
"0x69e2600fb277818102ac42be499b446d18e81e1c3bee5f8519af5ee9f08e5ea",
"0xb5040530d9560b356d37cadc580a676b020a45d8a0f94a6dfc2dfce8f248905",
"0x18d4e669f9d42f5b9227f2466b0f9f92eb2a5803897c96d92d4eb543192e8596",
"0x18755dbc62ea99f2d05fadbcff1072414e56d6a97fac8d6f8dee228716e06052",
"0xa343716d51e9a7760c51d16ce3559ab25029bb0f7473b6ec45c421089ab3aca",
"0x104778b84efe237b952fcd554206b0b41c5b10521a82070038a433726d091ee8",
"0x14ad00017ddffd06aff06b4f2cfe7c41cb42bbf7c8ac8027bbbfabc52d01fb6a",
"0xbb2d3c6b0ea6c1fe650995bf3eac551d3649b947469694d7d936f9be22eb752",
"0x21485bdfe5420da9cb6afb78a3754bf8888d39de80dd9436fd73ead03153d86",
"0x133ea01b153c99068bd38c5655fac3814836879305726716e959957b6bdc094f",
"0x17a59c3ec1e5d45d2258faf046158644a83f50267d7ca9dea1d0578d8487daf8",
"0xdb4b51f2913c829209f943736c79baf5e3a232d1c652dadb244dc8ec09ee008",
"0x4b1a86bab94be6c8e49c88a95ec1e9e44e6c57a35df55fb7718689cdc750ef5",
"0xc0c184efca03e842494486c261cfccc1ed63678ff322e85cb98b5fb022628b5",
"0x198d79443c806e39bb1ad4f13981aac2ee4f3dd82bd85eba474f5c10c0596337",
"0xbbae8bdcd8bdf8d849ff293a9fb35e505702bc3fd15c538eb2a458fdb658bd",
"0xb42c64d1e3a674911f8fac4bc9dbbc395ea590781c211e27722d87f3938b8a8",
"0x36550ce105e693453525baabec72e470c89499b08f95d8cdf6542ee6e9901b8",
"0x86e7c7a81ca1160d3076954b6a0ba13366d2e27d61e6369f4f72a753eb8ccf9",
"0x68f11d3fd113214c73310ea13e6bf9c9a0b9146276c804fc596b19dc08197c3",
"0x1c8d1d9643ca09b52838ca212539bc728b7b4838b7354d478bdd61060623e5db",
"0x93789e6ceb5c1e92de0d2c0aa256c273c0427d48279374b84d7d3e317041276",
"0x17c7ff4dca534d862bbbb0c3280398905d0c94d6f3874f416d29783b01b26190",
"0xb8dd71e65ba7dde01951bce28b2c3ebc16e32d79596f84abef7eef6cb21c5db",
"0x1b4083df87b2916c11f04454bea1e9a7f1ce85919363c7174b4d7de98a80a197",
"0x1bf995c1625803a5dd3bf31178dfbcb9656880d544f3e92ea936c113600dc742",
"0x1c9b1abb1d80e6f4f4f0131e8cd01b3ec5344d688a133333ff67a38783d64768",
"0x1a59d210ed96f594f2abaf1045686f716df84be90849e8ba3d985abc7e3e0619",
"0x42737022ca2d64017ec51b9a04aa71743d5790779dee150e1bbc6145d3538b",
"0x538d38861cc87fc9380230e1cb390f3f499ff5c213b6846c1b728630b2d12e6",
"0x765a731891db83489961cc75563a1932241c155b0dfc7f061d08b4feee2684f",
"0x1b53cfc62b27154ff56a5661e4ff03176cb580f73a64695246b09f4079e4f3aa",
"0x292a0dcf1447375e63c6cc55803741ced3f1b4b1408764bddf95a4e7e3952c5",
"0xd3bd70f533afa6cd285cd4e32e959eb2c585cb98763047bc1c25c685a01e7e",
"0x1a4814c1faca8528faa4f84143b358c828fbdc2e3171cf969894303f6bfc9edc",
"0x17a774001c6a1459ea871913dfbf2083a16574bb12c3aa05ef7f6a2dd5258f6e",
"0xece1ea76c41f98317126f72a85d1ec1eaacb064fdfc329572acf9e995496f99",
"0x158b876990da0d8a1a49cf71ec321d64133aed690afb893c0c19a25c5f66f90c",
"0x12b4e1a740e5ece84520994ba38a203df6b78261c5262395e481dc3efccda9bf",
"0x2e60f225eb812372b0ca3fe912c2e45a2b37ced7b67ab924a84363f11fbd0b8",
"0x225f0da70efefd9943812185c3d33cb7cb8b5f38f7c2b02217910fc1c309fab",
"0x8fa6324739559083080972682c52edbffaacf8569bb97170613d5a6e0036776",
"0xe5301ba9880a8354cf97759ba8ff5772490175f62f4bedef2e4b9dd9c9bef1c",
"0x17bb348644fdb12063d753998480182e91e5ab97f0d137e2bb2443404c48b85c",
"0x15838bccd094adb0629226b6b61bb7cc0a1fa2aa0eb21a885c07e5f827fb14bf",
"0x1ae6b9122460ca2db7ec61b978d97fafdc02dc5458517da4e5e5abd536eb438f",
"0x91459c7d491a99f1e9e4c1ea9e15952b96158442d1a57b95a477b182559cbc4",
"0xb70f5b2bea3c9e6343ac7ee1049a43e934b709634554e02d77fb5a229499b98",
"0xcf36f96d9c5565bd6f27518dcd9b64743282b86228a66c02d72c634943bf352",
"0x124e44037d47a853f780cceb67f481a8ca26aa8f8473d9381edb470e890ad9c",
"0xe1c9e73e3bb6a41a6d7df2498d2fd70154d201c7b79f4a723c49127ff5cf241",
"0xbd81f1aa1bd170812c1afd84bc501541cf7ffc3a1ac24c6d13f0f11cd53f9b",
"0xcea0353d1d809009bcd9aae32ea30633972b94d1950aed905a5f4e0c0897a1e",
"0xbb2c1077dd89b543945995317e3aeee2d3181a4800e77377e620bdf7b28b657",
"0xabe61c16fc4957f2354e90109d390ac62f892fbac2a15bd4f7dc0e13ec97d7b",
"0xf2a56357d214d73832434bd19cbe5fc3f51618497b749b686c1f45e52bb5710",
"0x6997777c8726b2236476bc60c39eb27a06a502a4a300d82018ef66384c82832",
"0x15820d8ed23a4386943124fe4a29a0f0a8a39c4007e53d88e86bf268e917915d",
"0x144721a9aa4b5debeec766d07e51bb314a2e91c3ddcdfda2a72c65ca2327f0af",
"0x7bf48dacfb035e2db129436ad6a8a304bafc65140a695e0b4e1cb2cd0a36765",
"0x11347ec9425b37459ac351be450129385d89f914a93066459b45cdb0a38bcfdf",
"0xa994a3eca1b2e98966304c11927f7c5cb937fc62bee43c99e29d0bdf96fee40",
"0xbf0e7267514b835b983767ca749cfe9b22bbb5038e97c372cc8e8f2f55add5d",
"0x77156c3f10b12c2d97a83dbac65d1d5b68a020c738f7a606efc08cefb6ed1e",
"0x149bbfdec357bc6ab8a1e881c431405395cdc08a2e037745ce008a2125024981",
"0xb595795727d85ce1bbe335fd682256a559e407153bf59d4a831b3c760fa605a",
"0xfd0644de5a300cf63f1d4b6ad5cc9c5f910f4b14fb71a1a5fd738a6955fa8c5",
"0xefc9032787f0c28a634254f6e79aee2cfa26250f6edf99f21337fc997206d45",
"0x16ecdf09390c386d88a430b43b9c9ece22afc38852d8f38f61c30c2f95ffbaff",
"0xca4e0987eb66920f1f1d96824550604a18fa2b18b6f96c5cd40b5c4648b1313",
"0x555a38f3691f86a28eaca1b7bd1e2911ae485d80da232b53042d7102c507b95",
"0x104e1787dd56101a387a54a82eb28f5bdeb5aaa8768632d5509f92d0da275be7",
"0x1579e6afd8836b82ae1f5a0c3ac59a28e1d99b2ee68919900ffbe9571101249a",
"0x126804b00b31cabce3c704ab6fb74e8c8331d837cddc40793d212729044835ea",
"0x1726fe00d974f56563685d9c73f2e9214355f6581790ec5a97b4c0db2b5d0e01",
"0x117002ea420da2e651f556c28a44e938c6ee5ae7946a1075372d3e8aaf7e2916",
"0x15667510c64a12517fb30df7b10052c2e1618cbfcb7bf245e0cb40592fbbf03",
"0xcd6575981c2d223e68e301df01fe806628b052f9b60fabcfaa6ff3c41cf83b7",
"0x73b0d2a29b744045913938f12d3599c7ba946c7c5a3e739b2189d2cad2eb23b",
"0x169d0302c1754dc3dd40ca67cb58b42299e7f75356edca8ccd4f274ef0ed6cf8",
"0xfc457942e4f4978260d30c6adb14d6f8094d966bc1a4bd7d5f2f5f29702f800",
"0x14420a97febbe3fea8e74fc5affc3769ac1dc1504b004e88114ca8b73e32bcfa",
"0xd57216b26deade6ab2e3cbdc0268a55ea6bde117b88c5f748b1bb225bff04a7",
"0x137ca3f7a8751be0b59a3e40e928598bc42d32b2ace38cdbc6689457712e72a0",
"0x12c304e12dc2c9a09d712d78841997de1507eb9991f9f5df6a4a5b746db0baf0",
"0x8484bb3f7d9e283119ea8b5d3436b560d5f4f4671902e14da822a74854ad45b",
"0xdcf212df7c1d5636686ae94c46a8dc6b1d1fdc9e9eab438aff15a755bd0b219",
"0x1b8a511e5a5650e951a1e10f4d0dd151448868a142dfe710f2d7aba1861a6c08",
"0x215a7608128fb33e425adcec5d1fcfbf83da4cb19a4c1a17b2916226ec884a4",
"0x7b6f5fba3651e64349b177c9c4b6f9820c81e41ce39dc6edd8e2fd3aad41366",
"0x1c0eac07519c56d7e604167da387fc3edf0645e3203e68e3bf4fe18a141f799d",
"0x7424b0fcb85587ae297de5a876584aa0d1ae2d769f94ec48cfa09e1a897ddcc",
"0xfccb80c72cb1afd20e4332a8e486de86c9880a48f607c875658a91d7a33fb7b",
"0xbd725397f714a58dc66d622cf31ca568980f43200fb653aefd82dc5f3793c0c",
"0xf1ab3f1af1674082c5dad9c6436e374b31aa6e7de329b7715469a6b8d1d0b6",
"0x18058c038daa84b2c4bf8fe05b49c2471d0461e7370294d3bf5fc6a47596ecdd",
"0x2f41988920be213d6c66d0cfef2a2e6caa66f1b5b3f68e1a660db9341bb3863",
"0x14ee4e171feb630db8a94dfafaaab3155b46a6f850adec48686996261d28cebb",
"0x96df0406a3bae4e779e10a04cf8ad22766c2d7220fa04fa312d95755cb13fb3",
"0x658616aa7db8ca3885ce8f7466c3fb501a86ec72f70e0eff0e2eda46ed21ae5",
"0xa45cd8cd1217ded0a929c2169dda6bbd213bf789ff9433afc0ec994c575dea9",
"0x14b8b5842ede8f406842bed9095c4487ddf7576ee117c01aeb6fb2d6cf7def8c",
"0xab420af7d502c8dd47f863793d4d3e24e49415b80f2aad6cabc45f036a5e71b",
"0x17d29c09f52c33d629b580292ff11a8db3f1ceea4b52bb50961299b9c3069070",
"0xf26d5b7cb1fddb18109c8eceec0d7c1d9e1bd4baf2084d018926b750368a290",
"0x1146aeed7fc1427884e6868771e44a328e097f2d32a61540b2f5087654116006",
"0x13ff9e7b5ba1b2cc2c35718f02b2fab419e5eddb8fb66e3f974a2ce6761cd9c5",
"0x13ec8b2d82404e826b15d5f22d11461535c59d1f07deed7d1703560ab52a2665",
"0xcbbe207d67da788af3d1b2a855e3f15b144a93c3fcd54e2721c93962cd52c78",
"0xfd6eda800d4e38ab79d85899479739e097aa0bbae6c31f480e834930542ee9c",
"0xdfc5330cb561807753f0fb863416cb29d03fbe521f4561f8ecd85a50520d400",
"0x5553ee1b1231cbe84c3da67da8609f56f42df1f069dc374e90640eb61d2f01a",
"0x14fa72e8c880ba3f34bbf586d1e587eeca3751e9b14d4ed259eba78fe78cbd7a",
"0x1a9d94a172a7c9729901bfb3607d9259b3267586730374c66ce8bd39323926c5",
"0xf18fef27f22766e26261178b90b288f8b8f25246e05f232a9ac431875976f49",
"0x1547f1fa7000b47e947fd54847d94e81ea44c02a3e1ec6f155f8d5fb654a3fdd",
"0x17c7f4fa7f40f6486ac482b45f3b733875ea84a156daf50a25c4d9f8acde9952",
"0x1eedba6ec73abf1b2fb4438e788bb74907e321bf1de295862fcef636d63e2a0",
"0xe6e35457bb0737d2ba03a37740300010946ded849c5917e5c1a59dd5d1546a1",
"0xcb6d8f842430db8d08372980a8c70584ff01d142c116fe2dc314056e583fd2f",
"0xfd1004f3bfb7baf2559a7c0c935b1d51e6181a3bc985e3ffb04f8225b8c6834",
"0x92170f5eaf701b5edeebd4fcc15ae98a6dc62e615ca7ef208c317eddab3e0f5",
"0x17d1dbf58503d835bd1f7917798fc0fb9140015db5b906fa0637b381f36d26e3",
"0xb1265122232a9b845781a6892a70e6e9f9a6be838956eebf5de0270c02c13e9",
"0x381b7be172d17558c4cf662d97909c2dce99e670854207c9b1f153e95a1e34b",
"0x713a24bf25fa56e5f9d336380ce55c35accedc7c56429a444000dc17bfaf2fc",
"0x1a824311c8d86fe7ab4ea1ef69bfdb053e34b5cfb3f1de0e1aeb6c716a6f5824",
"0x17666b2865824de8104bbd524a5aea4b41104b40b1f877f81871317699293cd5",
"0x16abf2bd2453251ff3180b072e80f4608485c9ef66e777cd56cebeea500b7d49",
"0x6290025172dbd4de4510d6ed406823c19b5a81cb39944a5effa789d5de4612c",
"0x14a44cd23a61ca1488c9bed51520eb66f020aa66ae7ec5489bad228024f4e365",
"0x122ebb340cd60624a63041a38ff8172053c7b6023d36cd7f577cfeca44f8a034",
"0x64230581d82d2b7f422bc654e8c962360133073a8bf9f47faaf8b7c3c8335d5",
"0x386494f4b96640c3b7f40901ab641b056e068986c2bba7ab46f3941b1a47e80",
"0x1ba5d39ba40110af30425db50e724b93a75bde8ad94667521b8290a87f72bf85",
"0xfbebc4481bfdd5c7725cbb640fb976da89fc5afcd5ecb740182e4548b57a73d",
"0x158d71db3af60eb27e1184e655a51aff7fab3a676a60847404c4f551a440f046",
"0x124c296d108aae7fb5973f3313a16d9286bf1529e5d7e59995506a5ca61eb7c7",
"0xbce3c9a42a536c81d0f60037f82cba600f0ec6e51e74ef3589ccc38b8e6e3b5",
"0x19609ac28bb9a4cce37adc3ed19e5d79b61187bc649616f7853977ee85a955c8",
"0x291dc12d149cea41c51de6cd183a2ffa925594c73e268c607d00347907363a0",
"0xc3974ab5505e4b75e04933e505bd2781217b082cd260d33284a1eedf6b5953e",
"0x9df1e680366930641475234087f807a4e569671b8e805dfd442f7653e48bc38",
"0x1a8fe523b30406a81612959ed8228030b6f9704ab8e8ab0403968b0ae5e0c33b",
"0x2f459df38eed6753ef8a0f4545fa6114f1c8f61c323245f2a98a67ee35a2972",
"0x1431690b5d5588bc75bfe17876645497c1d4cf1e3068f78f4b932f459196e30b",
"0x11bcc1b2787a95c18f2c72c5c50511fbec83b66f3851baa429b71aa3b777002c",
"0xf6efc0c898593e455d1eb64cf235bc5738497f0042e862329b275acb60b8834",
"0x1766a671c6f443bb248ca226789b7afbcc39b51219e248a630baa28a57be31ff",
"0xf9f17f85bc58b51265fd01c595cd6200d21e273e1aa38f55b7804186cb43c1d",]
