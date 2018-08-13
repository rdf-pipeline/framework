#!/usr/bin/env python3

# Copyright 2018 by David Booth 
# This software is available as free and open source under 
# the Apache 2.0 software license, which may be viewed at
# http://www.apache.org/licenses/LICENSE-2.0.html
# Code home: https://github.com/rdf-pipeline/framework
    
# Sparql Template Expander
# See the documentation for Perl module RDF::Pipeline::Template at
# https://github.com/rdf-pipeline/framework/wiki/Template-Processor
# This python version was ported from ste.perl on 12-Aug-2018.

# coding: utf-8

# In[95]:


import sys
import argparse
import os
import re
import urllib.parse
import json


# In[122]:


################### ScanAndAddInputs ####################
def ScanAndAddInputs(template, pValues, pHash={}):
    # # Called as:
    # # ($template, $pHash) =
    # #    &ScanAndAddInputs($template, $pValues, $pHash)
    return ScanAndAddToHash('inputs', template, pValues, pHash)

################### ScanAndAddOutputs ####################
def ScanAndAddOutputs(template, pValues, pHash={}):
    # # Called as:
    # # ($template, $pHash) =
    # #    &ScanAndAddOutputs($template, $pValues, $pHash);
    return ScanAndAddToHash("outputs", template, pValues, pHash);

################### ScanAndAddToHash ####################
def ScanAndAddToHash(keyword, template, pValues, pHash={}):
    # # Scan $template for a list of variables specified by the given $keyword,
    # # then add variable/value pairs to the given hashref, using that list
    # # and the given list of values, which must be the same length.
    # # If no hashRef is given, a new one will be created.
    # # The hashref is returned.
    template, pVars = ScanForList(keyword, template)
    pHash = AddPairsToHash(pVars, pValues, pHash)
    return template, pHash

# template, pHash = ScanAndAddToHash('inputs', "One\n#inputs(a b) \nThree", [1, 2])
# print("template: "+template)
# print("pHash: ", pHash)


# In[136]:


################### ScanAndAddParameters ####################
def ScanAndAddParameters(template, queryString='', pHash={}):
    # # Scan $template for a list of parameters, which is removed from
    # # the returned $template.  Then, to the given hashref,
    # # add the corresponding values from the given $queryString.
    # # In selecting the values from the $queryString, delimiters are
    # # stripped from the variables, using &BaseVar($_).
    pVars = []
    template, pVars = ScanForList("parameters", template)
    qsHash = ParseQueryString(queryString)
    errorTemplate = "[ERROR] Duplicate template variable: {}\n"
    for v in pVars:
        #   # Split param1=pVar1 if needed.
        paramVar = re.split(r'\=', v, 2)
        param = v
        var = v
        if len(paramVar) > 1:
            param = paramVar[0]
            var = paramVar[1]
        if var in pHash:
            raise Exception(errorTemplate.format(var))
        value = qsHash.get(BaseVar(param)) or ''
        pHash[var] = value
    return template, pHash

# ScanAndAddParameters('one\n#parameters(a b)\nthree', 'b=BB&c=CC')


# In[86]:


################### ScanForList ####################
def ScanForList(keyword, template):
    # # Scan $template for a declared list of variable names, such as:
    # # #inputs( $foo ${fum} )
    # # which is removed from the returned $template.  Also returns a list ref
    # # of the variable names found in the declared list.
    # # The given $keyword should normally be "inputs", "outputs" or "parameters",
    # # but may be some other word if this code is used for something else.
    inVars = []
    # # Process one line at a time, to preserve ordering.
    lines = re.split(r'\n', template, 0, re.MULTILINE)
    newLines = []
    for template in lines:
        # Given keyword "inputs", the pattern matches a line like:
        #       #inputs( $foo ${fum} )
        pattern = r'\#{}\(\s*([^\(\)]+?)\s*\)(.*)(\n|$)'.format(keyword)
        m = re.match(pattern, template)
        if m:
            inList = m.group(1)
            extra = m.group(2)
            line = m.group(0)

            ### Do not allow trailing comment:
            ### $extra =~ s/\A\#.*//;
            extra = re.sub(r'\A\s*', '', extra)
            if extra:
                raise Exception("[ERROR] Extra text after #{}(...): {}".format(keyword, extra))
            inVars.extend(re.split(r'\s+', inList))
        else:
            newLines.append(template)
    template = '\n'.join(newLines)
    return template, inVars

# ScanForList('inputs', "One\n#inputs(a b) \nThree")


# In[68]:


################### ScanAndAddEnvs ####################
def ScanAndAddEnvs(template, pEnvs={}):
    # # Scan $template for $ENV{foo} references and add each one (as a key)
    # # to the given hashref, where its value will be the value of that
    # # environment variable (or empty string, if not set).
    # # If no hashref is given, one will be created.
    # # The hashref is returned.  Existing values in the hashref will be
    # # silently overwritten if a duplicate key is used.
    # # The $template is not modified, and therefore not returned.
    if template is None:
        raise Exception('ScanAndAddEnvs called with None as template!')
    vvars = re.findall(r'\$ENV\{(\w+)\}', template, re.IGNORECASE)
    for var in vvars:
        pEnvs['$ENV{'+var+'}'] = os.environ.get(var) or ''

    return pEnvs

# os.environ['HELLO'] = 'hello'
# ScanAndAddEnvs('HELLO is $ENV{HELLO} var')


# In[ ]:


################### AddPairsToHash #####################
def AddPairsToHash(pVars, pVals, pRep={}):
    # Add pairs of corresponding values from the two arrayrefs to the
    # given hashref.  If no hashref is given, a new one will be created.
    # The hashref is returned.
    # An error will be generated if a duplicate key is seen.
    nVars = len(pVars)
    nVals = len(pVals)
    if nVars < nVals:
        raise Exception("[ERROR] {} values provided for {} template variables ({})\n".format(nVals, nVars, " ".join(pVars)))
    errorTemplate = "[ERROR] duplicate template variable: {}\n";
    for i, var in enumerate(pVars):
        if var in pRep:
            raise Exception(errorTemplate.format(var))
        val = ''
        if i < len(pVals):
            val = pVals[i]
        pRep[var] = val
    return pRep


# In[ ]:


################### ParseQueryString ####################
def ParseQueryString(qs, hashref={}):
    # # Create (or add to) a hashref that maps query string variables to values.
    # # Both variables and values are uri_unescaped.
    # # Example:
    # #   'foo=bar&fum=bif'  --> { 'foo'=>'bar', 'fum'=>'bif' }
    # # If there is a duplicate variable then the latest one silently
    # # takes priority.  If no hashref is given, a new one will be created.
    # # The hashref is returned.
    # # Per http://www.w3.org/TR/1999/REC-html401-19991224/appendix/notes.html#h-B.2.2
    # # also allow semicolon to be treated as ampersand separator:
    pairs = re.split(r'[\&\;]', qs)
    for pair in pairs:
        varVal = re.split(r'\=', pair)
        var = varVal[0]
        val = ''
        if len(varVal) > 1:
            val = varVal[1]
        if len(var) > 0:
            hashref[urllib.parse.unquote(var)] = urllib.parse.unquote(val)
    return hashref

# ParseQueryString('foo=bar&baz=bam')


# In[ ]:


################# BaseVar ####################
def BaseVar(dv):
    # # Given a string like '${foo}' (representing a declared variable),
    # # return a new string with the delimiters stripped off: 'fum'.
    # # This is for variables that are used as query string parameters,
    # # such as: http://example/whatever?foo=bar
    # # For simplicity, variable names must match \w+ .
    m = re.match(r'\W*(\w+)\W*$', dv)
    if m is None:
        raise Exception('Bad template variable in #parameters(...): {}\n'.format(dv))
    baseVar = m.group(1)
    return baseVar

# BaseVar('[$foo--')


# In[ ]:


################### ExpandTemplate ####################
def ExpandTemplate(template, pRep):
    # # Expand the given template, substituting variables for values.
    # # Variable/value pairs are provided in the given hashref.
    if template is None:
        return None
    #   # Ensure that words aren't run together:
    #   # \$foo --> \$foo\b ;  foo --> \bfoo\b
    keys = [ re.escape(k) for k in pRep.keys()]
    keys = [ re.sub(r'\A(\w)', r'\\b\1', k) for k in keys]
    keys = [ re.sub(r'(\w)\Z', r'\1\\b', k) for k in keys]
    pattern = ')|('.join(keys)
    if (keys and len(pattern) > 0):
        pattern = '(('+pattern+'))'
        def pRepGroup(m):
            return pRep[m.group()]
        template = re.sub(pattern, pRepGroup, template)
    return template

# ExpandTemplate('foo food baz business', {'foo': 'bar', 'baz': 'bam'})


# In[71]:


##################### ProcessTemplate #######################
def ProcessTemplate(template, pInputs, pOutputs, queryString, thisUri):
    # Scan and expand a template containing variable declarations like:
    #       #inputs( $in1 ${in2} )
    #       #outputs( {out1} [out2] )
    #       #parameters( $foo ${fum} )
    # $queryString supplies values for variables declared as "#parameters",
    # such as: foo=bar&fum=bif&foe=bah
    # Environment variables will also be substituted where they occur
    # like $ENV{foo}, though if $thisUri is set then it will be used as the
    # value of $ENV{THIS_URI} regardless of what was set in the environment.
    # $pInputs and $pOutputs are array references supplying values
    # for declared "#inputs" and "#outputs".
    # The function dies if duplicate declared variables are detected.
    if template is None:
        raise Exception('ProcessTemplate called with None as template!')
    pRep = ScanAndAddEnvs(template)
    # # $thisUri (if set) takes precedence:
    if thisUri is not None:
        pRep['$ENV{THIS_URI}'] = thisUri
    # Scan for input, output and parameter vars and add them:
    template, pRep = ScanAndAddInputs(template, pInputs, pRep)
    template, pRep = ScanAndAddOutputs(template, pOutputs, pRep)
    template, pRep = ScanAndAddParameters(template, queryString, pRep)
    # Expand the template and we're done:
    result = ExpandTemplate(template, pRep)
    return result

# ProcessTemplate('HELLO is $ENV{HELLO} var', [], [], 'bar=BAR', 'urn:local:myUri2')


# In[137]:



################### GetArgsAndProcessTemplate ###################
def GetArgsAndProcessTemplate():
    ins = []
    outs = []
    params = []
    thisUri = None
    
    parser = argparse.ArgumentParser(description="Simple template expansion.")
    parser.add_argument('-i', '--inputs', action='append',
                      help='Value(s) to be substituted for #inputs variable(s)')
    parser.add_argument('-o', '--outputs', action='append',
                      help='Value(s) to be substituted for #outputs variable(s)')
    parser.add_argument('-p', '--parameters', action='append',
                      help='Value(s) to be substituted for #parameters variable(s).\n'+
                        '    Can also be set in $QUERY_STRING.')
    parser.add_argument('-t', '--thisUri', nargs=1, default=None,
                      help='URI of this node.  Can also be set in $THIS_URI.')
    parser.add_argument('inFile', default=None,
                      help='Template filename')
   
    options = parser.parse_args()
    ins = options.inputs or []
    outs = options.outputs or []
    paramsArray = options.parameters or []
    if paramsArray:
        params = [re.sub(r'[&;]+$','',re.sub(r'^[&;]+','',p)) for p in paramsArray]
        os.environ['QUERY_STRING'] = '&'.join(params)
    params = os.environ.get('QUERY_STRING') or ''
    
    if options.thisUri:
        os.environ['THIS_URI'] = options.thisUri[0]
    thisUri = os.environ.get('THIS_URI') or ''

    template = ''
    if options.inFile:
        with open(options.inFile, "r", encoding='utf8') as f:
            template = f.read()
    else:
        template = sys.stdin.read()
    result = ProcessTemplate(template, ins, outs, params, thisUri)
    sys.stdout.write(result)

# sys.argv = ["ste.py", "-p", "foo", "-p", "bar", "-t", "urn:local:myUri", "/tmp/foo"]
# GetArgsAndProcessTemplate()


# In[33]:




####################### Usage #######################
def Usage(*args):
    # warn @_ if @_;
    if args:
        sys.stderr.write(''.join(args)+'\n')
    sys.stderr.write('''Usage: {} [template] [ -i iVal1 ...] [ -o oVal1 ...] [ -p pVar1=pVal1 ...]
Arguments:
  template
        Filename of SPARQL template to use instead of stdin.

Options:
  -i iVal1 ...
        Values to be substituted into variables specified
        by "#inputs( $iVar1 ... )" lines in template.

  -o oVal1 ...
        Values to be substituted into variables specified
        by "#outputs( $oVar1 ... )" lines in template.

  -p pVar1=pVal1 ...
        URI encoded variable/value pairs to be substituted
        into variables specified by "#parameters( $pVar1 ... )"
        lines in template.  Both variables and
        values will be uri_unescaped before use.  Multiple
        variable/value pairs may be specified together using
        "&" as separator: foo=bar&fum=bah&foe=bif .  If -p
        option is not used, then URI-encoded variable/value
        pairs will be taken from the QUERY_STRING environment
        variable, which is ignored if -p is used.

  -t thisUri
        Causes thisUri to be substituted for $ENV{{THIS_URI}}
        in template, overriding whatever value was set in
        the environment.
'''.format(os.path.basename(sys.argv[0])))

# Usage()


# In[ ]:


############################ main #################################
if __name__ == '__main__':
    GetArgsAndProcessTemplate()
    sys.exit(0)

