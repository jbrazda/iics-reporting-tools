module namespace util = 'iics/util';


(:~
 : Capitalizes a string.
 : @param  $string  string
 : @return capitalized string
 :)
declare function util:capitalize(
  $string  as xs:string
) as xs:string {
  upper-case(substring($string, 1, 1)) || substring($string, 2)
};