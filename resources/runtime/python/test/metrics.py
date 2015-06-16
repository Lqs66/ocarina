#! /usr/bin/python

import sys
import getopt
import StringIO

def printError(source, messages):
    print 'Error while calling ' , source
    for message in messages:
        print message

def main(argv):
    '''Test function'''
    import OcarinaPython as ocarina
    
    aadlFiles = ''
    root = ''
    
    try:
        opts, args = getopt.getopt(argv,"ha:r:",["aadlFiles=","root="])
    except getopt.GetoptError:
        print 'Error in command options. Usage is:'
        print 'metrics.py -a <aadlfile>[,<aadlfile>]* -r <root object>'
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print 'Usage is:'
            print 'metrics.py -a <aadlfile>[,<aadlfile>]* -r <root object>'
            sys.exit()
        elif opt in ("-a", "--aadlFiles"):
            aadlFiles = arg.split(',')
        elif opt in ("-r", "--root"):
            root = arg

    if root == '' :
        print 'Root object shall be defined. Usage is:'
        print 'metrics.py -a <aadlfile>[,<aadlfile>]* -r <root object>'
        sys.exit(2)
    if aadlFiles == '' :
        print 'At least one aadl file shall be loaded. Usage is:'
        print 'metrics.py -a <aadlfile>[,<aadlfile>]* -r <root object>'
        sys.exit(2)
    
    for aadlFile  in aadlFiles:
        err = ocarina.load(aadlFile)
        if err[3]!=[]:
            printError('ocarina.load('+aadlFile+')', err[3])
            sys.exit(2)
    err = ocarina.analyze() 
    if err[3]!=[]:
        printError('ocarina.analyze()', err[3])
        sys.exit(2)
    err = ocarina.instantiate(root)
    if err[3]!=[]:
        printError('ocarina.instantiate('+root+')', err[3])
        sys.exit(2)

    print '----------------------------------------------------'
    print 'Number of Component Instances:'
    print '----------------------------------------------------'
    aadlInstances=ocarina.getInstances('processor')[0]
    print '- Processors:\t\t',len(aadlInstances)
    aadlInstances=ocarina.getInstances('process')[0]
    print '- Processes:\t\t',len(aadlInstances)
    aadlInstances=ocarina.getInstances('thread')[0]
    print '- Threads:\t\t',len(aadlInstances)
    aadlInstances=ocarina.getInstances('subprogram')[0]
    print '- Subprograms:\t\t',len(aadlInstances)
    print '----------------------------------------------------'
    print '           *** DECLARATIVE MODEL ***'
    print '----------------------------------------------------'
    aadlPackages=ocarina.getPackages()[0]
    print 'Number of Packages:\t\t\t',len(aadlPackages)
    aadlCompoTypes=ocarina.getComponentTypes('all')[0]
    print 'Number of Component Types:\t\t',len(aadlCompoTypes)
    aadlCompoImpl=ocarina.getComponentImplementations('all')[0]
    print 'Number of Component Implementations:\t',len(aadlCompoImpl)
    aadlSubcomponents=[]
    for impl in aadlCompoImpl:
        tmp=ocarina.ATN.Subcomponents(impl)[0]
        if tmp is not None :
            aadlSubcomponents=aadlSubcomponents+tmp
    print 'Number of Subcomponents:\t\t',len(aadlSubcomponents)
    aadlCalls=[]
    for impl in aadlCompoImpl:
        tmp=ocarina.ATN.Calls(impl)[0]
        if tmp is not None :
            aadlCalls=aadlCalls+tmp
    print 'Number of Call Sequences:\t\t',len(aadlCalls)
    aadlSubprogramCalls=[]
    for call in aadlCalls:
        aadlSubprogramCalls=aadlSubprogramCalls+ocarina.ATN.Subprogram_Calls(call)[0]
    print 'Number of Subprogram Calls:\t\t',len(aadlSubprogramCalls)
    aadlFeatures=[]
    for type in aadlCompoTypes:
        tmp=ocarina.ATN.Features(type)[0]
        if tmp is not None :
            aadlFeatures=aadlFeatures+tmp
    print 'Number of Features:\t\t\t',len(aadlFeatures)
    aadlConnections=[]
    for impl in aadlCompoImpl:
        tmp=ocarina.ATN.Connections(impl)[0]
        if tmp is not None :
            aadlConnections=aadlConnections+tmp
    print 'Number of Connections:\t\t\t',len(aadlConnections)
    aadlProperties=[]
    for elt in aadlCompoTypes+aadlCompoImpl+aadlFeatures+aadlConnections:
        tmp=ocarina.ATN.Properties(elt)[0]
        if tmp is not None :
            aadlProperties=aadlProperties+tmp
    print 'Number of Property Associations:\t',len(aadlProperties)
    print '---- Prototypes ------------------------------------'
    knownAadlElt=ocarina.getPrototypes()[0]
    print 'Number of Prototypes:\t\t\t',len(knownAadlElt)
    knownAadlElt=ocarina.getPrototypeBindings()[0]
    print 'Number of Prototype Bindings:\t\t',len(knownAadlElt)
    print '---- Flows -----------------------------------------'
    knownAadlElt=ocarina.getFlowSpecifications()[0]
    print 'Number of Flow Specifications:\t\t',len(knownAadlElt)
    knownAadlElt=ocarina.getFlowImplementations()[0]
    print 'Number of Flow Implementations:\t\t',len(knownAadlElt)
    print '---- Modes -----------------------------------------'
    knownAadlElt=ocarina.getModes()[0]
    print 'Number of Modes:\t\t\t',len(knownAadlElt)
    knownAadlElt=ocarina.getModeTransitions()[0]
    print 'Number of Mode Transitions:\t\t',len(knownAadlElt)
    print '---- Properties ------------------------------------'
    aadlPropertySets=ocarina.getPropertySets()[0]
    print 'Number of Property Sets:\t\t',len(aadlPropertySets)
    aadlPropertyTypes=[]
    for propSet in aadlPropertySets:
        tmp=ocarina.getPropertyTypes(propSet)[0]
        if tmp is not None :
            aadlPropertyTypes=aadlPropertyTypes+tmp
    print 'Number of Property Types:\t\t',len(aadlPropertyTypes)
    aadlPropertyDefinitions=[]
    for propSet in aadlPropertySets:
        tmp=ocarina.getPropertyDefinitions(propSet)[0]
        if tmp is not None :
            aadlPropertyDefinitions=aadlPropertyDefinitions+tmp
    print 'Number of Property Definitions:\t\t',len(aadlPropertyDefinitions)
    aadlPropertyConstants=[]
    for propSet in aadlPropertySets:
        tmp=ocarina.getPropertyConstants(propSet)[0]
        if tmp is not None :
            aadlPropertyConstants=aadlPropertyConstants+tmp
    print 'Number of Property Constants:\t\t',len(aadlPropertyConstants)
    print '---- Annexes ---------------------------------------'
    aadlAnnexes=ocarina.getAnnexes()[0]
    print 'Number of Annexes:\t\t\t',len(aadlAnnexes)

if __name__ == "__main__":
    main(sys.argv[1:])
    sys.exit (0)                       # exit
